-- Bakery Tracker Supabase database setup
-- Run this in Supabase SQL Editor on a NEW project.
-- Do not run this script twice without using the reset/drop section.
-- Uses auth.uid() and the authenticated user's own rows.

create extension if not exists "uuid-ossp";

create table public.products (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  image_url text,
  category text not null default 'bakery',
  is_archived boolean not null default false,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint products_title_not_blank check (length(trim(title)) > 0),
  constraint products_category_valid check (category in ('bakery', 'merchandise'))
);

create table public.customers (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  phone text,
  is_archived boolean not null default false,
  -- Free-text customer group/location (e.g. "Office", "Central") - the set
  -- of valid group names is configured client-side (Settings), not
  -- enforced here, since it's just a customer-defined label.
  group_name text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint customers_name_not_blank check (length(trim(name)) > 0)
);

create table public.batches (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id),
  legacy_id integer,
  batch_date date not null,
  count_produced integer not null,
  unit_price numeric(12,2) not null,
  unit_cost numeric(12,2) not null default 0,
  total_value numeric(12,2) not null,
  remitted boolean not null default false,
  date_remitted date,
  locked boolean not null default false,
  is_personal boolean not null default false,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint batches_count_positive check (count_produced > 0),
  constraint batches_prices_nonnegative check (unit_price >= 0 and unit_cost >= 0),
  constraint batches_total_nonnegative check (total_value >= 0)
);

create table public.sales (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  batch_id uuid not null references public.batches(id),
  customer_id uuid not null references public.customers(id),
  legacy_id integer,
  sale_date date not null,
  quantity integer not null default 1,
  amount numeric(12,2) not null,
  paid boolean not null default false,
  date_paid date,
  sale_type text not null default 'customer_sale',
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint sales_quantity_positive check (quantity > 0),
  constraint sales_amount_nonnegative check (amount >= 0),
  constraint sales_type_valid check (sale_type in ('customer_sale', 'unsold', 'internal_consumption', 'points_redemption')),
  constraint sales_payment_date_valid check (paid = true or date_paid is null)
);

-- Manual loyalty-points corrections (goodwill credits, error fixes) that
-- aren't tied to a real purchase, so they can't be represented as a sales
-- row (which requires a batch and a positive quantity). Points can be
-- positive or negative; category keeps it in the same separate pool as
-- normal earning/redemption for that category.
create table public.loyalty_adjustments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  category text not null,
  points integer not null,
  reason text,
  adjustment_date date not null default current_date,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint loyalty_adjustments_category_valid check (category in ('bakery', 'merchandise')),
  constraint loyalty_adjustments_points_nonzero check (points <> 0)
);

-- Which products a customer likes, so a new batch of that product can
-- prompt a heads-up. A pure on/off preference with no history value, so
-- unlike every other table here it's hard-deleted on remove rather than
-- soft-deleted - there's nothing worth keeping once un-favorited.
create table public.customer_favorites (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  product_id uuid not null references public.products(id),
  created_at timestamptz not null default now(),
  primary key (customer_id, product_id)
);

-- Indexes for RLS, sync, joins, dashboard queries, and sorting.
create index products_user_id_idx on public.products(user_id);
create index products_updated_at_idx on public.products(updated_at);
create index customers_user_id_idx on public.customers(user_id);
create index customers_updated_at_idx on public.customers(updated_at);
create index batches_user_id_idx on public.batches(user_id);
create index batches_updated_at_idx on public.batches(updated_at);
create index batches_product_id_idx on public.batches(product_id);
create index sales_user_id_idx on public.sales(user_id);
create index sales_updated_at_idx on public.sales(updated_at);
create index sales_batch_id_idx on public.sales(batch_id);
create index sales_customer_id_idx on public.sales(customer_id);
create index loyalty_adjustments_user_id_idx on public.loyalty_adjustments(user_id);
create index loyalty_adjustments_customer_id_idx on public.loyalty_adjustments(customer_id);
create index loyalty_adjustments_updated_at_idx on public.loyalty_adjustments(updated_at);
create index customer_favorites_user_id_idx on public.customer_favorites(user_id);
create index customer_favorites_product_id_idx on public.customer_favorites(product_id);

-- Product/customer uniqueness is scoped to each user and ignores soft-deleted rows.
create unique index products_user_title_unique
on public.products(user_id, lower(title))
where is_deleted = false;

create unique index customers_user_name_unique
on public.customers(user_id, lower(name))
where is_deleted = false;

-- Ensure product and customer foreign keys cannot be used across users.
create or replace function public.validate_bakery_owner_relationship()
returns trigger
language plpgsql
security invoker
as $$
declare
  related_user_id uuid;
begin
  if tg_table_name = 'batches' then
    select user_id into related_user_id from public.products where id = new.product_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Product does not belong to the same user';
    end if;
  elsif tg_table_name = 'sales' then
    select user_id into related_user_id from public.batches where id = new.batch_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Batch does not belong to the same user';
    end if;
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'loyalty_adjustments' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'customer_favorites' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
    select user_id into related_user_id from public.products where id = new.product_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Product does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_batches_owner_relationship
before insert or update on public.batches
for each row execute function public.validate_bakery_owner_relationship();

create trigger trg_sales_owner_relationship
before insert or update on public.sales
for each row execute function public.validate_bakery_owner_relationship();

create trigger trg_loyalty_adjustments_owner_relationship
before insert or update on public.loyalty_adjustments
for each row execute function public.validate_bakery_owner_relationship();

create trigger trg_customer_favorites_owner_relationship
before insert or update on public.customer_favorites
for each row execute function public.validate_bakery_owner_relationship();

-- Automatically update timestamps on changed records.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_products_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create trigger trg_customers_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create trigger trg_batches_updated_at
before update on public.batches
for each row execute function public.set_updated_at();

create trigger trg_sales_updated_at
before update on public.sales
for each row execute function public.set_updated_at();

create trigger trg_loyalty_adjustments_updated_at
before update on public.loyalty_adjustments
for each row execute function public.set_updated_at();

-- Enable Row Level Security.
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.batches enable row level security;
alter table public.sales enable row level security;
alter table public.loyalty_adjustments enable row level security;
alter table public.customer_favorites enable row level security;

-- One authenticated account can access only its own rows.
create policy products_owner_access
on public.products for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy customers_owner_access
on public.customers for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy batches_owner_access
on public.batches for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy sales_owner_access
on public.sales for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy loyalty_adjustments_owner_access
on public.loyalty_adjustments for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy customer_favorites_owner_access
on public.customer_favorites for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- RLS policies only govern row visibility once a role already has base
-- table privileges; without these grants every query is rejected before
-- RLS is even evaluated (Postgres error 42501).
grant usage on schema public to authenticated;
grant select, insert, update, delete
  on public.products, public.customers, public.batches, public.sales,
     public.loyalty_adjustments, public.customer_favorites
  to authenticated;

-- Run this against an already-created database to add the "personal batch,
-- skip remittance" flag without re-running the whole script.
alter table public.batches add column if not exists is_personal boolean not null default false;

-- Run this against an already-created database to add legacy-id columns
-- (idempotent XLSX re-import matching, now that import runs against
-- Supabase directly instead of a local database) without re-running the
-- whole script.
alter table public.batches add column if not exists legacy_id integer;
alter table public.sales add column if not exists legacy_id integer;
create unique index if not exists batches_user_legacy_id_unique
  on public.batches(user_id, legacy_id) where legacy_id is not null;
create unique index if not exists sales_user_legacy_id_unique
  on public.sales(user_id, legacy_id) where legacy_id is not null;

-- Run this against an already-created database to allow the "redeemed for
-- loyalty points" sale type without re-running the whole script.
alter table public.sales drop constraint if exists sales_type_valid;
alter table public.sales add constraint sales_type_valid
  check (sale_type in ('customer_sale', 'unsold', 'internal_consumption', 'points_redemption'));

-- Product photo storage bucket.
insert into storage.buckets (id, name, public)
values ('product-photos', 'product-photos', true)
on conflict (id) do nothing;

-- Public read is intentional for product images.
create policy product_photos_public_read
on storage.objects for select
using (bucket_id = 'product-photos');

-- Files must be stored as <user_id>/<product_id>.<extension>.
create policy product_photos_owner_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'product-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy product_photos_owner_update
on storage.objects for update to authenticated
using (
  bucket_id = 'product-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'product-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy product_photos_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'product-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Run this against an already-created database to add product categories
-- (Bakery / Merchandise), which keep each category's loyalty points pool
-- separate, without re-running the whole script.
alter table public.products add column if not exists category text not null default 'bakery';
alter table public.products drop constraint if exists products_category_valid;
alter table public.products add constraint products_category_valid
  check (category in ('bakery', 'merchandise'));

-- Run this against an already-created database to allow archiving
-- discontinued products (hidden from pickers, kept for historical batches)
-- without re-running the whole script.
alter table public.products add column if not exists is_archived boolean not null default false;

-- Run this against an already-created database to add manual loyalty-points
-- adjustments (goodwill credits, error corrections) without re-running the
-- whole script.
create table if not exists public.loyalty_adjustments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  category text not null,
  points integer not null,
  reason text,
  adjustment_date date not null default current_date,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint loyalty_adjustments_category_valid check (category in ('bakery', 'merchandise')),
  constraint loyalty_adjustments_points_nonzero check (points <> 0)
);
create index if not exists loyalty_adjustments_user_id_idx on public.loyalty_adjustments(user_id);
create index if not exists loyalty_adjustments_customer_id_idx on public.loyalty_adjustments(customer_id);
create index if not exists loyalty_adjustments_updated_at_idx on public.loyalty_adjustments(updated_at);

create or replace function public.validate_bakery_owner_relationship()
returns trigger
language plpgsql
security invoker
as $$
declare
  related_user_id uuid;
begin
  if tg_table_name = 'batches' then
    select user_id into related_user_id from public.products where id = new.product_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Product does not belong to the same user';
    end if;
  elsif tg_table_name = 'sales' then
    select user_id into related_user_id from public.batches where id = new.batch_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Batch does not belong to the same user';
    end if;
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'loyalty_adjustments' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_loyalty_adjustments_owner_relationship on public.loyalty_adjustments;
create trigger trg_loyalty_adjustments_owner_relationship
before insert or update on public.loyalty_adjustments
for each row execute function public.validate_bakery_owner_relationship();

drop trigger if exists trg_loyalty_adjustments_updated_at on public.loyalty_adjustments;
create trigger trg_loyalty_adjustments_updated_at
before update on public.loyalty_adjustments
for each row execute function public.set_updated_at();

alter table public.loyalty_adjustments enable row level security;

drop policy if exists loyalty_adjustments_owner_access on public.loyalty_adjustments;
create policy loyalty_adjustments_owner_access
on public.loyalty_adjustments for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.loyalty_adjustments to authenticated;

-- Run this against an already-created database to add a free-text customer
-- group/location label (e.g. "Office", "Central") without re-running the
-- whole script. The set of valid group names is configured client-side
-- (Settings), not enforced here.
alter table public.customers add column if not exists group_name text;

-- Run this against an already-created database to add customer favorites
-- (which products a customer likes, for a heads-up when you bake one)
-- without re-running the whole script.
create table if not exists public.customer_favorites (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  product_id uuid not null references public.products(id),
  created_at timestamptz not null default now(),
  primary key (customer_id, product_id)
);
create index if not exists customer_favorites_user_id_idx on public.customer_favorites(user_id);
create index if not exists customer_favorites_product_id_idx on public.customer_favorites(product_id);

create or replace function public.validate_bakery_owner_relationship()
returns trigger
language plpgsql
security invoker
as $$
declare
  related_user_id uuid;
begin
  if tg_table_name = 'batches' then
    select user_id into related_user_id from public.products where id = new.product_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Product does not belong to the same user';
    end if;
  elsif tg_table_name = 'sales' then
    select user_id into related_user_id from public.batches where id = new.batch_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Batch does not belong to the same user';
    end if;
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'loyalty_adjustments' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'customer_favorites' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
    select user_id into related_user_id from public.products where id = new.product_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Product does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_customer_favorites_owner_relationship on public.customer_favorites;
create trigger trg_customer_favorites_owner_relationship
before insert or update on public.customer_favorites
for each row execute function public.validate_bakery_owner_relationship();

alter table public.customer_favorites enable row level security;

drop policy if exists customer_favorites_owner_access on public.customer_favorites;
create policy customer_favorites_owner_access
on public.customer_favorites for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.customer_favorites to authenticated;

-- Realtime publication.
-- If any of these tables are already in the publication, run the statement
-- individually and ignore the "already a member" error.
alter publication supabase_realtime add table public.products;
alter publication supabase_realtime add table public.customers;
alter publication supabase_realtime add table public.batches;
alter publication supabase_realtime add table public.sales;
alter publication supabase_realtime add table public.loyalty_adjustments;
alter publication supabase_realtime add table public.customer_favorites;

-- Optional convenience view for the web dashboard. The Flutter app can also
-- calculate analytics locally from its repository lists.
create or replace view public.sales_with_details as
select
  s.id,
  s.user_id,
  s.batch_id,
  s.customer_id,
  s.sale_date,
  s.quantity,
  s.amount,
  s.paid,
  s.date_paid,
  s.sale_type,
  s.notes,
  s.updated_at,
  s.is_deleted,
  c.name as customer_name,
  b.product_id,
  b.batch_date,
  p.title as product_title
from public.sales s
join public.customers c on c.id = s.customer_id
join public.batches b on b.id = s.batch_id
join public.products p on p.id = b.product_id
where s.is_deleted = false;

-- The view inherits table RLS through the underlying tables in normal use.
-- Do not expose it to the client until needed; the app can query base tables.
