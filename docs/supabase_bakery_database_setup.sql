-- Bakery Tracker Supabase database setup
-- Existing databases: do not rerun this full file. Apply the dated scripts
-- under docs/migrations instead.
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
  -- Purely informational: how much was knocked off the full
  -- quantity*unit_price to arrive at `amount`. `amount` remains the actual
  -- charged/owed figure everywhere else in the app.
  discount numeric(12,2) not null default 0,
  paid boolean not null default false,
  date_paid date,
  payment_method text,
  sale_type text not null default 'customer_sale',
  notes text,
  -- A reservation: the customer has committed to buying from this batch
  -- before it's actually ready/in stock, as opposed to a normal sale
  -- logged once it's available. Still counts toward allocated quantity -
  -- this is a display/organizational flag, not a different business rule.
  is_reservation boolean not null default false,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint sales_quantity_positive check (quantity > 0),
  constraint sales_amount_nonnegative check (amount >= 0),
  constraint sales_discount_nonnegative check (discount >= 0),
  constraint sales_type_valid check (sale_type in ('customer_sale', 'unsold', 'internal_consumption', 'points_redemption')),
  constraint sales_payment_date_valid check (paid = true or date_paid is null)
);

-- Installment/partial payments against an unpaid sale. The sale keeps its
-- full `amount`; it flips to `paid = true` only once the sum of its
-- payments covers that amount. A sale with no rows here and paid = true
-- was simply paid in full in one go (no installment history needed).
create table public.sale_payments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  sale_id uuid not null references public.sales(id),
  amount numeric(12,2) not null,
  payment_date date not null default current_date,
  payment_method text,
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint sale_payments_amount_positive check (amount > 0)
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

-- A running credit ledger per customer - e.g. they overpaid because a
-- batch's unit price was corrected downward after they'd already paid at
-- the old (higher) price. Positive amount = credit owed to the customer;
-- negative = credit consumed (applied to a later purchase) or refunded in
-- cash. Balance = sum of amounts. Not auto-applied to future sales - it's
-- surfaced in the UI so the person taking the next order can deduct it
-- manually, since the customer may prefer a cash refund instead.
create table public.customer_credits (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  amount numeric(12,2) not null,
  reason text,
  sale_id uuid references public.sales(id),
  credit_date date not null default current_date,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint customer_credits_amount_nonzero check (amount <> 0)
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

-- Marks a customer-favorite "handled" for one specific batch (the Dashboard
-- stops nagging about it), without un-favoriting the product - the same
-- customer's favorite will surface again for the *next* batch of that
-- product. Pure on/off marker, hard-deleted like customer_favorites.
create table public.favorite_dismissals (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  batch_id uuid not null references public.batches(id),
  created_at timestamptz not null default now(),
  primary key (customer_id, batch_id)
);

-- Standalone business expenses (rent, utilities, packaging, ...) that
-- aren't tied to a batch's own unit cost - feeds into the Dashboard's net
-- profit figure alongside batch cost-of-goods.
create table public.expenses (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount numeric(12,2) not null,
  category text not null default 'Other',
  expense_date date not null default current_date,
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint expenses_amount_positive check (amount > 0)
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
create index sale_payments_user_id_idx on public.sale_payments(user_id);
create index sale_payments_sale_id_idx on public.sale_payments(sale_id);
create index customer_credits_user_id_idx on public.customer_credits(user_id);
create index customer_credits_customer_id_idx on public.customer_credits(customer_id);
create index favorite_dismissals_user_id_idx on public.favorite_dismissals(user_id);
create index favorite_dismissals_batch_id_idx on public.favorite_dismissals(batch_id);
create index expenses_user_id_idx on public.expenses(user_id);
create index expenses_expense_date_idx on public.expenses(expense_date);

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
  elsif tg_table_name = 'sale_payments' then
    select user_id into related_user_id from public.sales where id = new.sale_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Sale does not belong to the same user';
    end if;
  elsif tg_table_name = 'customer_credits' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'favorite_dismissals' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
    select user_id into related_user_id from public.batches where id = new.batch_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Batch does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

-- Remitted-sale immutability ------------------------------------------------
-- Database enforcement is required because Flutter-side checks can race or
-- be bypassed by another client. Reopen/unlock the remittance before changing
-- or soft-deleting one of its transactions.
create or replace function public.prevent_remitted_sale_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.batches b
    where b.id = old.batch_id
      and b.user_id = auth.uid()
      and b.locked
  ) then
    raise exception 'Transactions in a locked batch cannot be changed. Unlock the batch first.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'UPDATE'
     and new.batch_id is distinct from old.batch_id
     and exists (
       select 1
       from public.batches b
       where b.id = new.batch_id
         and b.user_id = auth.uid()
         and b.locked
     ) then
    raise exception 'Transactions cannot be moved into a locked batch.'
      using errcode = 'P0001';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_prevent_remitted_sale_mutation on public.sales;
create trigger trg_prevent_remitted_sale_mutation
before update or delete on public.sales
for each row execute function public.prevent_remitted_sale_mutation();

create or replace function public.prevent_remitted_payment_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  target_sale_id uuid;
begin
  target_sale_id := case when tg_op = 'DELETE' then old.sale_id else new.sale_id end;
  if exists (
    select 1
    from public.sales s
    join public.batches b on b.id = s.batch_id
    where s.id = target_sale_id
      and s.user_id = auth.uid()
      and b.locked
  ) then
    raise exception 'Payments in a locked batch cannot be changed. Unlock the batch first.'
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_prevent_remitted_payment_mutation on public.sale_payments;
create trigger trg_prevent_remitted_payment_mutation
before insert or update or delete on public.sale_payments
for each row execute function public.prevent_remitted_payment_mutation();

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

create trigger trg_sale_payments_owner_relationship
before insert or update on public.sale_payments
for each row execute function public.validate_bakery_owner_relationship();

create trigger trg_customer_credits_owner_relationship
before insert or update on public.customer_credits
for each row execute function public.validate_bakery_owner_relationship();

create trigger trg_favorite_dismissals_owner_relationship
before insert or update on public.favorite_dismissals
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

create trigger trg_sale_payments_updated_at
before update on public.sale_payments
for each row execute function public.set_updated_at();

create trigger trg_customer_credits_updated_at
before update on public.customer_credits
for each row execute function public.set_updated_at();

create trigger trg_expenses_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

-- Enable Row Level Security.
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.batches enable row level security;
alter table public.sales enable row level security;
alter table public.loyalty_adjustments enable row level security;
alter table public.customer_favorites enable row level security;
alter table public.sale_payments enable row level security;
alter table public.customer_credits enable row level security;
alter table public.favorite_dismissals enable row level security;
alter table public.expenses enable row level security;

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

create policy sale_payments_owner_access
on public.sale_payments for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy customer_credits_owner_access
on public.customer_credits for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy favorite_dismissals_owner_access
on public.favorite_dismissals for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy expenses_owner_access
on public.expenses for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- RLS policies only govern row visibility once a role already has base
-- table privileges; without these grants every query is rejected before
-- RLS is even evaluated (Postgres error 42501).
grant usage on schema public to authenticated;
grant select, insert, update, delete
  on public.products, public.customers, public.batches, public.sales,
     public.loyalty_adjustments, public.customer_favorites, public.sale_payments,
     public.customer_credits, public.favorite_dismissals, public.expenses
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

-- Payment QR code storage bucket (up to 3 slots per user, shown on
-- statement PDFs) - same public-read / owner-write shape as product photos.
insert into storage.buckets (id, name, public)
values ('qr-codes', 'qr-codes', true)
on conflict (id) do nothing;

create policy qr_codes_public_read
on storage.objects for select
using (bucket_id = 'qr-codes');

-- Files must be stored as <user_id>/qr_<slot>.<extension>.
create policy qr_codes_owner_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy qr_codes_owner_update
on storage.objects for update to authenticated
using (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy qr_codes_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'qr-codes'
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

-- Run this against an already-created database to track a discount amount
-- separately from the sale's charged `amount`, without re-running the
-- whole script.
alter table public.sales add column if not exists discount numeric(12,2) not null default 0;
alter table public.sales drop constraint if exists sales_discount_nonnegative;
alter table public.sales add constraint sales_discount_nonnegative check (discount >= 0);

-- Run this against an already-created database to add installment/partial
-- payments against an unpaid sale without re-running the whole script. The
-- sale keeps its full `amount`; it flips to `paid = true` only once the sum
-- of its payments covers that amount.
create table if not exists public.sale_payments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  sale_id uuid not null references public.sales(id),
  amount numeric(12,2) not null,
  payment_date date not null default current_date,
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint sale_payments_amount_positive check (amount > 0)
);
create index if not exists sale_payments_user_id_idx on public.sale_payments(user_id);
create index if not exists sale_payments_sale_id_idx on public.sale_payments(sale_id);

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
  elsif tg_table_name = 'sale_payments' then
    select user_id into related_user_id from public.sales where id = new.sale_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Sale does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sale_payments_owner_relationship on public.sale_payments;
create trigger trg_sale_payments_owner_relationship
before insert or update on public.sale_payments
for each row execute function public.validate_bakery_owner_relationship();

drop trigger if exists trg_sale_payments_updated_at on public.sale_payments;
create trigger trg_sale_payments_updated_at
before update on public.sale_payments
for each row execute function public.set_updated_at();

alter table public.sale_payments enable row level security;

drop policy if exists sale_payments_owner_access on public.sale_payments;
create policy sale_payments_owner_access
on public.sale_payments for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.sale_payments to authenticated;

-- Run this against an already-created database to record which payment
-- method (Cash, GCash, etc - configurable in Settings) was used, without
-- re-running the whole script.
alter table public.sales add column if not exists payment_method text;
alter table public.sale_payments add column if not exists payment_method text;

-- Run this against an already-created database to add a per-customer
-- credit ledger (e.g. for a batch unit-price correction after a customer
-- already paid at the old price) without re-running the whole script.
create table if not exists public.customer_credits (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  amount numeric(12,2) not null,
  reason text,
  sale_id uuid references public.sales(id),
  credit_date date not null default current_date,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint customer_credits_amount_nonzero check (amount <> 0)
);
create index if not exists customer_credits_user_id_idx on public.customer_credits(user_id);
create index if not exists customer_credits_customer_id_idx on public.customer_credits(customer_id);

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
  elsif tg_table_name = 'sale_payments' then
    select user_id into related_user_id from public.sales where id = new.sale_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Sale does not belong to the same user';
    end if;
  elsif tg_table_name = 'customer_credits' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_customer_credits_owner_relationship on public.customer_credits;
create trigger trg_customer_credits_owner_relationship
before insert or update on public.customer_credits
for each row execute function public.validate_bakery_owner_relationship();

drop trigger if exists trg_customer_credits_updated_at on public.customer_credits;
create trigger trg_customer_credits_updated_at
before update on public.customer_credits
for each row execute function public.set_updated_at();

alter table public.customer_credits enable row level security;

drop policy if exists customer_credits_owner_access on public.customer_credits;
create policy customer_credits_owner_access
on public.customer_credits for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.customer_credits to authenticated;

-- Run this against an already-created database to add reservations (a sale
-- committed before the batch is actually ready), a per-batch dismiss for
-- the favorites-in-stock heads-up, and standalone business expenses,
-- without re-running the whole script.
alter table public.sales add column if not exists is_reservation boolean not null default false;

create table if not exists public.favorite_dismissals (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  batch_id uuid not null references public.batches(id),
  created_at timestamptz not null default now(),
  primary key (customer_id, batch_id)
);
create index if not exists favorite_dismissals_user_id_idx on public.favorite_dismissals(user_id);
create index if not exists favorite_dismissals_batch_id_idx on public.favorite_dismissals(batch_id);

create table if not exists public.expenses (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount numeric(12,2) not null,
  category text not null default 'Other',
  expense_date date not null default current_date,
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint expenses_amount_positive check (amount > 0)
);
create index if not exists expenses_user_id_idx on public.expenses(user_id);
create index if not exists expenses_expense_date_idx on public.expenses(expense_date);

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
  elsif tg_table_name = 'sale_payments' then
    select user_id into related_user_id from public.sales where id = new.sale_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Sale does not belong to the same user';
    end if;
  elsif tg_table_name = 'customer_credits' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
  elsif tg_table_name = 'favorite_dismissals' then
    select user_id into related_user_id from public.customers where id = new.customer_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Customer does not belong to the same user';
    end if;
    select user_id into related_user_id from public.batches where id = new.batch_id;
    if related_user_id is null or related_user_id <> new.user_id then
      raise exception 'Batch does not belong to the same user';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_favorite_dismissals_owner_relationship on public.favorite_dismissals;
create trigger trg_favorite_dismissals_owner_relationship
before insert or update on public.favorite_dismissals
for each row execute function public.validate_bakery_owner_relationship();

drop trigger if exists trg_expenses_updated_at on public.expenses;
create trigger trg_expenses_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

alter table public.favorite_dismissals enable row level security;
alter table public.expenses enable row level security;

drop policy if exists favorite_dismissals_owner_access on public.favorite_dismissals;
create policy favorite_dismissals_owner_access
on public.favorite_dismissals for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists expenses_owner_access on public.expenses;
create policy expenses_owner_access
on public.expenses for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.favorite_dismissals to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;

-- Run this against an already-created database to add the payment QR code
-- storage bucket (up to 3 slots per user, shown on statement PDFs) without
-- re-running the whole script.
insert into storage.buckets (id, name, public)
values ('qr-codes', 'qr-codes', true)
on conflict (id) do nothing;

drop policy if exists qr_codes_public_read on storage.objects;
create policy qr_codes_public_read
on storage.objects for select
using (bucket_id = 'qr-codes');

drop policy if exists qr_codes_owner_insert on storage.objects;
create policy qr_codes_owner_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists qr_codes_owner_update on storage.objects;
create policy qr_codes_owner_update
on storage.objects for update to authenticated
using (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists qr_codes_owner_delete on storage.objects;
create policy qr_codes_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Realtime publication.
-- If any of these tables are already in the publication, run the statement
-- individually and ignore the "already a member" error.
alter publication supabase_realtime add table public.products;
alter publication supabase_realtime add table public.customers;
alter publication supabase_realtime add table public.batches;
alter publication supabase_realtime add table public.sales;
alter publication supabase_realtime add table public.loyalty_adjustments;
alter publication supabase_realtime add table public.customer_favorites;
alter publication supabase_realtime add table public.sale_payments;
alter publication supabase_realtime add table public.customer_credits;
alter publication supabase_realtime add table public.favorite_dismissals;
alter publication supabase_realtime add table public.expenses;

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

-- Customer SOA portal -------------------------------------------------------
-- Permanent, read-only customer statement links. Only a SHA-256 hash of each
-- bearer token is stored. Creating a replacement immediately invalidates the
-- previous link.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.customer_soa_links (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  token_hash bytea not null unique,
  -- Kept so the authenticated bakery owner can copy/share the same permanent
  -- link later. Anonymous lookups still compare only token_hash.
  token_value text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  last_accessed_at timestamptz,
  unique (user_id, customer_id)
);

-- Existing installations initially stored only the hash. Those links keep
-- working, but must be rotated once before they can be re-shared.
alter table public.customer_soa_links
add column if not exists token_value text;

create index if not exists customer_soa_links_user_id_idx
on public.customer_soa_links(user_id);

alter table public.customer_soa_links enable row level security;

drop policy if exists customer_soa_links_owner_access
on public.customer_soa_links;
create policy customer_soa_links_owner_access
on public.customer_soa_links for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete
on public.customer_soa_links to authenticated;

create or replace function public.customer_soa_link_status(p_customer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id
      and c.user_id = auth.uid()
      and not c.is_deleted
  ) then
    raise exception 'Customer not found';
  end if;

  select jsonb_build_object(
    'exists', true,
    'enabled', l.enabled,
    'token', l.token_value,
    'created_at', l.created_at,
    'last_accessed_at', l.last_accessed_at
  ) into result
  from public.customer_soa_links l
  where l.user_id = auth.uid() and l.customer_id = p_customer_id;

  return coalesce(result, jsonb_build_object(
    'exists', false,
    'enabled', false,
    'token', null,
    'created_at', null,
    'last_accessed_at', null
  ));
end;
$$;

create or replace function public.rotate_customer_soa_link(p_customer_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  token text;
begin
  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id
      and c.user_id = auth.uid()
      and not c.is_deleted
  ) then
    raise exception 'Customer not found';
  end if;

  token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.customer_soa_links (
    user_id, customer_id, token_hash, token_value, enabled, created_at, last_accessed_at
  ) values (
    auth.uid(),
    p_customer_id,
    extensions.digest(convert_to(token, 'UTF8'), 'sha256'),
    token,
    true,
    now(),
    null
  )
  on conflict (user_id, customer_id) do update set
    token_hash = excluded.token_hash,
    token_value = excluded.token_value,
    enabled = true,
    created_at = now(),
    last_accessed_at = null;

  return token;
end;
$$;

create or replace function public.revoke_customer_soa_link(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.customer_soa_links
  set enabled = false
  where user_id = auth.uid() and customer_id = p_customer_id;
end;
$$;

-- This is the only portal function available to anonymous visitors. It
-- returns one deliberately limited JSON document rather than granting anon
-- access to any underlying business table.
create or replace function public.get_customer_soa(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  link_record public.customer_soa_links%rowtype;
  business_name text;
  enabled_slots jsonb;
  balance numeric(12,2);
  sale_rows jsonb;
  qr_rows jsonb;
begin
  if p_token is null or length(p_token) <> 64 then
    raise exception 'Statement link is invalid';
  end if;

  select * into link_record
  from public.customer_soa_links l
  where l.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
    and l.enabled
  limit 1;

  if link_record.id is null then
    raise exception 'Statement link is invalid';
  end if;

  update public.customer_soa_links
  set last_accessed_at = now()
  where id = link_record.id;

  select
    coalesce(nullif(u.raw_user_meta_data->>'business_name', ''), 'My Bakery'),
    coalesce(u.raw_user_meta_data->'enabled_qr_slots', '[1,2,3]'::jsonb)
  into business_name, enabled_slots
  from auth.users u
  where u.id = link_record.user_id;

  select coalesce(sum(
    case
      when s.paid then 0
      else greatest(
        s.amount - coalesce((
          select sum(sp.amount)
          from public.sale_payments sp
          where sp.sale_id = s.id and not sp.is_deleted
        ), 0),
        0
      )
    end
  ), 0)
  into balance
  from public.sales s
  where s.user_id = link_record.user_id
    and s.customer_id = link_record.customer_id
    and s.sale_type = 'customer_sale'
    and not s.is_deleted;

  select coalesce(jsonb_agg(row_data order by sale_date desc), '[]'::jsonb)
  into sale_rows
  from (
    select
      s.sale_date,
      jsonb_build_object(
        'id', s.id,
        'sale_date', s.sale_date,
        'product', p.title,
        'quantity', s.quantity,
        'amount', s.amount,
        'paid', s.paid,
        'date_paid', s.date_paid,
        'payment_method', s.payment_method,
        'remaining', case
          when s.paid then 0
          else greatest(
            s.amount - coalesce((
              select sum(sp.amount)
              from public.sale_payments sp
              where sp.sale_id = s.id and not sp.is_deleted
            ), 0),
            0
          )
        end,
        'payments', coalesce((
          select jsonb_agg(jsonb_build_object(
            'amount', sp.amount,
            'date', sp.payment_date,
            'method', sp.payment_method
          ) order by sp.payment_date)
          from public.sale_payments sp
          where sp.sale_id = s.id and not sp.is_deleted
        ), '[]'::jsonb)
      ) as row_data
    from public.sales s
    join public.batches b on b.id = s.batch_id
    join public.products p on p.id = b.product_id
    where s.user_id = link_record.user_id
      and s.customer_id = link_record.customer_id
      and s.sale_type = 'customer_sale'
      and not s.is_deleted
  ) rows_for_customer;

  select coalesce(jsonb_agg(o.name order by o.name), '[]'::jsonb)
  into qr_rows
  from storage.objects o
  where o.bucket_id = 'qr-codes'
    and o.name ~ ('^' || link_record.user_id::text || '/qr_[1-3][.][A-Za-z0-9]+$')
    and exists (
      select 1
      from jsonb_array_elements_text(enabled_slots) slot(value)
      where slot.value = substring(o.name from 'qr_([0-9]+)[.]')
    );

  return jsonb_build_object(
    'business_name', business_name,
    'generated_at', now(),
    'customer', (
      select jsonb_build_object('name', c.name)
      from public.customers c
      where c.id = link_record.customer_id
    ),
    'balance', balance,
    'sales', sale_rows,
    'qr_paths', qr_rows
  );
end;
$$;

revoke all on function public.customer_soa_link_status(uuid) from public;
revoke all on function public.rotate_customer_soa_link(uuid) from public;
revoke all on function public.revoke_customer_soa_link(uuid) from public;
revoke all on function public.get_customer_soa(text) from public;

grant execute on function public.customer_soa_link_status(uuid) to authenticated;
grant execute on function public.rotate_customer_soa_link(uuid) to authenticated;
grant execute on function public.revoke_customer_soa_link(uuid) to authenticated;
grant execute on function public.get_customer_soa(text) to anon, authenticated;

-- Transactional backup v2 restore ------------------------------------------
-- The Flutter client validates structure and references before calling these
-- functions. PostgreSQL performs the complete restore in one transaction.
create or replace function public.preview_backup_v2(p_backup jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  row_count integer := 0;
  stale_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  if coalesce((p_backup->>'version')::integer, 0) <> 2 then
    raise exception 'Only complete backup version 2 is supported';
  end if;

  select coalesce(sum(jsonb_array_length(coalesce(p_backup->key_name, '[]'::jsonb))), 0)
  into row_count
  from unnest(array[
    'products', 'customers', 'batches', 'sales', 'sale_payments',
    'customer_credits', 'loyalty_adjustments', 'expenses',
    'customer_favorites', 'favorite_dismissals'
  ]) key_name;

  select
    (select count(*) from jsonb_array_elements(p_backup->'products') r
      join public.products t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'customers') r
      join public.customers t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'batches') r
      join public.batches t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'sales') r
      join public.sales t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'sale_payments') r
      join public.sale_payments t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'customer_credits') r
      join public.customer_credits t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'loyalty_adjustments') r
      join public.loyalty_adjustments t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz) +
    (select count(*) from jsonb_array_elements(p_backup->'expenses') r
      join public.expenses t on t.id = (r->>'remote_id')::uuid
      where t.user_id = auth.uid() and t.updated_at > (r->>'updated_at')::timestamptz)
  into stale_count;

  return jsonb_build_object(
    'row_count', row_count,
    'stale_conflicts', stale_count
  );
end;
$$;

create or replace function public.restore_backup_v2(
  p_backup jsonb,
  p_allow_stale boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  r jsonb;
  preview jsonb;
  product_uuid uuid;
  customer_uuid uuid;
  batch_uuid uuid;
  sale_uuid uuid;
  existed boolean;
  products_created integer := 0; products_updated integer := 0;
  customers_created integer := 0; customers_updated integer := 0;
  batches_created integer := 0; batches_updated integer := 0;
  sales_created integer := 0; sales_updated integer := 0;
  dependent_rows integer := 0;
begin
  preview := public.preview_backup_v2(p_backup);
  if not p_allow_stale and (preview->>'stale_conflicts')::integer > 0 then
    raise exception 'The live database contains newer rows. Preview and explicitly confirm stale overwrite.';
  end if;

  for r in select value from jsonb_array_elements(p_backup->'products') loop
    select exists(select 1 from public.products where id = (r->>'remote_id')::uuid and user_id = auth.uid()) into existed;
    insert into public.products(id, user_id, title, image_url, category, is_archived, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), r->>'title', r->>'image_url',
      coalesce(r->>'category', 'bakery'), coalesce((r->>'is_archived')::boolean, false),
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set
      title = excluded.title, image_url = excluded.image_url,
      category = excluded.category, is_archived = excluded.is_archived,
      is_deleted = false
    where products.user_id = auth.uid();
    if existed then products_updated := products_updated + 1; else products_created := products_created + 1; end if;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'customers') loop
    select exists(select 1 from public.customers where id = (r->>'remote_id')::uuid and user_id = auth.uid()) into existed;
    insert into public.customers(id, user_id, name, phone, is_archived, group_name, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), r->>'name', r->>'phone',
      coalesce((r->>'is_archived')::boolean, false), r->>'group_name',
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set
      name = excluded.name, phone = excluded.phone,
      is_archived = excluded.is_archived, group_name = excluded.group_name,
      is_deleted = false
    where customers.user_id = auth.uid();
    if existed then customers_updated := customers_updated + 1; else customers_created := customers_created + 1; end if;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'batches') loop
    select (p->>'remote_id')::uuid into product_uuid
    from jsonb_array_elements(p_backup->'products') p
    where (p->>'id')::integer = (r->>'product_id')::integer;
    select exists(select 1 from public.batches where id = (r->>'remote_id')::uuid and user_id = auth.uid()) into existed;
    insert into public.batches(id, user_id, product_id, legacy_id, batch_date,
      count_produced, unit_price, unit_cost, total_value, remitted,
      date_remitted, locked, is_personal, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), product_uuid,
      (r->>'legacy_id')::integer, (r->>'batch_date')::date,
      (r->>'count_produced')::integer, (r->>'unit_price')::numeric,
      coalesce((r->>'unit_cost')::numeric, 0), (r->>'total_value')::numeric,
      false, null, false,
      coalesce((r->>'is_personal')::boolean, false),
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set
      product_id = excluded.product_id, legacy_id = excluded.legacy_id,
      batch_date = excluded.batch_date, count_produced = excluded.count_produced,
      unit_price = excluded.unit_price, unit_cost = excluded.unit_cost,
      total_value = excluded.total_value, remitted = excluded.remitted,
      date_remitted = excluded.date_remitted, locked = excluded.locked,
      is_personal = excluded.is_personal, is_deleted = false
    where batches.user_id = auth.uid();
    if existed then batches_updated := batches_updated + 1; else batches_created := batches_created + 1; end if;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'sales') loop
    select (b->>'remote_id')::uuid into batch_uuid
    from jsonb_array_elements(p_backup->'batches') b
    where (b->>'id')::integer = (r->>'batch_id')::integer;
    select (c->>'remote_id')::uuid into customer_uuid
    from jsonb_array_elements(p_backup->'customers') c
    where (c->>'id')::integer = (r->>'customer_id')::integer;
    select exists(select 1 from public.sales where id = (r->>'remote_id')::uuid and user_id = auth.uid()) into existed;
    insert into public.sales(id, user_id, batch_id, customer_id, legacy_id,
      sale_date, quantity, amount, discount, paid, date_paid, payment_method,
      sale_type, notes, is_reservation, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), batch_uuid, customer_uuid,
      (r->>'legacy_id')::integer, (r->>'sale_date')::date,
      coalesce((r->>'quantity')::integer, 1), (r->>'amount')::numeric,
      coalesce((r->>'discount')::numeric, 0), coalesce((r->>'paid')::boolean, false),
      (r->>'date_paid')::date, r->>'payment_method',
      coalesce(r->>'sale_type', 'customer_sale'), r->>'notes',
      coalesce((r->>'is_reservation')::boolean, false),
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set
      batch_id = excluded.batch_id, customer_id = excluded.customer_id,
      legacy_id = excluded.legacy_id, sale_date = excluded.sale_date,
      quantity = excluded.quantity, amount = excluded.amount,
      discount = excluded.discount, paid = excluded.paid,
      date_paid = excluded.date_paid, payment_method = excluded.payment_method,
      sale_type = excluded.sale_type, notes = excluded.notes,
      is_reservation = excluded.is_reservation, is_deleted = false
    where sales.user_id = auth.uid()
      and (sales.batch_id, sales.customer_id, sales.legacy_id, sales.sale_date,
        sales.quantity, sales.amount, sales.discount, sales.paid,
        sales.date_paid, sales.payment_method, sales.sale_type, sales.notes,
        sales.is_reservation, sales.is_deleted)
      is distinct from
      (excluded.batch_id, excluded.customer_id, excluded.legacy_id,
        excluded.sale_date, excluded.quantity, excluded.amount,
        excluded.discount, excluded.paid, excluded.date_paid,
        excluded.payment_method, excluded.sale_type, excluded.notes,
        excluded.is_reservation, false);
    if existed then sales_updated := sales_updated + 1; else sales_created := sales_created + 1; end if;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'sale_payments') loop
    select (s->>'remote_id')::uuid into sale_uuid from jsonb_array_elements(p_backup->'sales') s where (s->>'id')::integer = (r->>'sale_id')::integer;
    insert into public.sale_payments(id, user_id, sale_id, amount, payment_date, payment_method, notes, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), sale_uuid, (r->>'amount')::numeric,
      (r->>'payment_date')::date, r->>'payment_method', r->>'notes',
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set sale_id = excluded.sale_id, amount = excluded.amount,
      payment_date = excluded.payment_date, payment_method = excluded.payment_method,
      notes = excluded.notes, is_deleted = false
    where sale_payments.user_id = auth.uid();
    dependent_rows := dependent_rows + 1;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'customer_credits') loop
    select (c->>'remote_id')::uuid into customer_uuid from jsonb_array_elements(p_backup->'customers') c where (c->>'id')::integer = (r->>'customer_id')::integer;
    sale_uuid := null;
    if r->>'sale_id' is not null then
      select (s->>'remote_id')::uuid into sale_uuid from jsonb_array_elements(p_backup->'sales') s where (s->>'id')::integer = (r->>'sale_id')::integer;
    end if;
    insert into public.customer_credits(id, user_id, customer_id, amount, reason, sale_id, credit_date, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), customer_uuid, (r->>'amount')::numeric,
      r->>'reason', sale_uuid, (r->>'credit_date')::date,
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set customer_id = excluded.customer_id,
      amount = excluded.amount, reason = excluded.reason, sale_id = excluded.sale_id,
      credit_date = excluded.credit_date, is_deleted = false
    where customer_credits.user_id = auth.uid();
    dependent_rows := dependent_rows + 1;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'loyalty_adjustments') loop
    select (c->>'remote_id')::uuid into customer_uuid from jsonb_array_elements(p_backup->'customers') c where (c->>'id')::integer = (r->>'customer_id')::integer;
    insert into public.loyalty_adjustments(id, user_id, customer_id, category, points, reason, adjustment_date, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), customer_uuid, r->>'category',
      (r->>'points')::integer, r->>'reason', (r->>'adjustment_date')::date,
      (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set customer_id = excluded.customer_id,
      category = excluded.category, points = excluded.points,
      reason = excluded.reason, adjustment_date = excluded.adjustment_date,
      is_deleted = false
    where loyalty_adjustments.user_id = auth.uid();
    dependent_rows := dependent_rows + 1;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'expenses') loop
    insert into public.expenses(id, user_id, amount, category, expense_date, notes, updated_at, is_deleted)
    values ((r->>'remote_id')::uuid, auth.uid(), (r->>'amount')::numeric,
      coalesce(r->>'category', 'Other'), (r->>'expense_date')::date,
      r->>'notes', (r->>'updated_at')::timestamptz, false)
    on conflict (id) do update set amount = excluded.amount,
      category = excluded.category, expense_date = excluded.expense_date,
      notes = excluded.notes, is_deleted = false
    where expenses.user_id = auth.uid();
    dependent_rows := dependent_rows + 1;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'customer_favorites') loop
    select (c->>'remote_id')::uuid into customer_uuid from jsonb_array_elements(p_backup->'customers') c where (c->>'id')::integer = (r->>'customer_id')::integer;
    select (p->>'remote_id')::uuid into product_uuid from jsonb_array_elements(p_backup->'products') p where (p->>'id')::integer = (r->>'product_id')::integer;
    insert into public.customer_favorites(user_id, customer_id, product_id)
    values (auth.uid(), customer_uuid, product_uuid)
    on conflict (customer_id, product_id) do nothing;
    dependent_rows := dependent_rows + 1;
  end loop;

  for r in select value from jsonb_array_elements(p_backup->'favorite_dismissals') loop
    select (c->>'remote_id')::uuid into customer_uuid from jsonb_array_elements(p_backup->'customers') c where (c->>'id')::integer = (r->>'customer_id')::integer;
    select (b->>'remote_id')::uuid into batch_uuid from jsonb_array_elements(p_backup->'batches') b where (b->>'id')::integer = (r->>'batch_id')::integer;
    insert into public.favorite_dismissals(user_id, customer_id, batch_id)
    values (auth.uid(), customer_uuid, batch_uuid)
    on conflict (customer_id, batch_id) do nothing;
    dependent_rows := dependent_rows + 1;
  end loop;

  -- Restore remittance state only after all child rows are complete. This is
  -- the explicit, transactional reopen window used solely by this RPC.
  for r in select value from jsonb_array_elements(p_backup->'batches') loop
    update public.batches
    set remitted = coalesce((r->>'remitted')::boolean, false),
        date_remitted = (r->>'date_remitted')::date,
        locked = coalesce((r->>'locked')::boolean, false)
    where id = (r->>'remote_id')::uuid and user_id = auth.uid();
  end loop;

  return jsonb_build_object(
    'products_created', products_created, 'products_updated', products_updated,
    'customers_created', customers_created, 'customers_updated', customers_updated,
    'batches_created', batches_created, 'batches_updated', batches_updated,
    'sales_created', sales_created, 'sales_updated', sales_updated,
    'dependent_rows_restored', dependent_rows
  );
end;
$$;

revoke all on function public.preview_backup_v2(jsonb) from public;
revoke all on function public.restore_backup_v2(jsonb, boolean) from public;
grant execute on function public.preview_backup_v2(jsonb) to authenticated;
grant execute on function public.restore_backup_v2(jsonb, boolean) to authenticated;
