-- Product reservations: a lightweight "lead" a public website visitor leaves
-- against a product from the public announce/reserve page (web/products.html),
-- *not* the existing sales.is_reservation flag (which is a committed sale
-- against a known customer/batch). These rows are just a heads-up for the
-- owner to follow up on and convert into a real sale manually; nothing here
-- touches batches/sales/inventory.
-- Run this complete file in the Supabase SQL Editor.

create table if not exists public.product_reservations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  -- Nullable + on delete set null: product_title is the display source of
  -- truth, so a later hard-deleted product doesn't need to take the
  -- reservation row down with it.
  product_id uuid references public.products(id) on delete set null,
  product_title text not null,
  customer_name text not null,
  customer_contact text not null,
  quantity integer not null default 1,
  note text,
  status text not null default 'pending',
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint product_reservations_quantity_positive check (quantity > 0),
  constraint product_reservations_status_valid check (status in ('pending', 'contacted', 'fulfilled', 'cancelled')),
  constraint product_reservations_name_not_blank check (length(trim(customer_name)) > 0),
  constraint product_reservations_contact_not_blank check (length(trim(customer_contact)) > 0)
);

create index if not exists product_reservations_user_status_idx
on public.product_reservations(user_id, status);

alter table public.product_reservations enable row level security;

drop policy if exists product_reservations_owner_access on public.product_reservations;
create policy product_reservations_owner_access on public.product_reservations
for all to authenticated using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.product_reservations to authenticated;

drop trigger if exists trg_product_reservations_updated_at on public.product_reservations;
create trigger trg_product_reservations_updated_at before update on public.product_reservations
for each row execute function public.set_updated_at();

-- Public, read-only: everything currently available across every batch
-- (personal batches are for sale too - "personal" here just marks which of
-- the two people running the business produced it, not that it's off the
-- market), summed per product, with that product's most recent batch price.
-- Single-tenant for now (no store/user selector on the public page), same
-- assumption the rest of this schema already makes - revisit alongside the
-- multi-user workspace redesign if that ever ships.
create or replace function public.get_available_products()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare business_name text; product_rows jsonb;
begin
  select coalesce(nullif(u.raw_user_meta_data->>'business_name', ''), 'My Bakery')
  into business_name from auth.users u order by u.created_at asc limit 1;

  select coalesce(jsonb_agg(row_data order by row_data->>'title'), '[]'::jsonb)
  into product_rows
  from (
    select jsonb_build_object(
      'id', agg.product_id,
      'title', agg.title,
      'image_url', agg.image_url,
      'category', agg.category,
      'remaining', agg.remaining,
      'unit_price', agg.unit_price
    ) as row_data
    from (
      select
        p.id as product_id,
        p.title,
        p.image_url,
        p.category,
        sum(b.count_produced - coalesce(sold.qty, 0) - coalesce(used.qty, 0)) as remaining,
        (array_agg(b.unit_price order by b.batch_date desc, b.id desc))[1] as unit_price
      from public.products p
      join public.batches b on b.product_id = p.id and not b.is_deleted
      left join (
        select batch_id, sum(quantity) as qty from public.sales
        where sale_type = 'customer_sale' and not is_deleted
        group by batch_id
      ) sold on sold.batch_id = b.id
      left join (
        select batch_id, sum(quantity) as qty from public.sales
        where sale_type = 'internal_consumption' and not is_deleted
        group by batch_id
      ) used on used.batch_id = b.id
      where not p.is_deleted and not p.is_archived
      group by p.id, p.title, p.image_url, p.category
    ) agg
    where agg.remaining > 0
  ) products_row;

  return jsonb_build_object(
    'generated_at', now(),
    'business_name', business_name,
    'products', product_rows
  );
end;
$$;
revoke all on function public.get_available_products() from public;
grant execute on function public.get_available_products() to anon, authenticated;

-- Public write: anyone with the announce page link can leave a reservation
-- request against one product. Looks up the product's own owner so this
-- still scopes correctly if the app ever becomes multi-tenant.
create or replace function public.submit_product_reservation(
  p_product_id uuid,
  p_customer_name text,
  p_customer_contact text,
  p_quantity integer default 1,
  p_note text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_title text;
  v_id uuid;
begin
  select user_id, title into v_user_id, v_title
  from public.products
  where id = p_product_id and not is_deleted;

  if v_user_id is null then raise exception 'Product not found'; end if;
  if p_customer_name is null or length(trim(p_customer_name)) = 0 then
    raise exception 'Name is required';
  end if;
  if p_customer_contact is null or length(trim(p_customer_contact)) = 0 then
    raise exception 'Contact is required';
  end if;
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Quantity must be at least 1';
  end if;

  insert into public.product_reservations(
    user_id, product_id, product_title, customer_name, customer_contact, quantity, note
  ) values (
    v_user_id, p_product_id, v_title, trim(p_customer_name), trim(p_customer_contact), p_quantity,
    nullif(trim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  return v_id;
end;
$$;
revoke all on function public.submit_product_reservation(uuid, text, text, integer, text) from public;
grant execute on function public.submit_product_reservation(uuid, text, text, integer, text) to anon, authenticated;

-- Add the new ledger to the app's one-request snapshot.
create or replace function public.get_app_snapshot()
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare result jsonb := '{}'::jsonb; rows jsonb; spec record;
begin
  for spec in select * from (values
    ('products','title','asc',true), ('customers','name','asc',true),
    ('batches','batch_date','desc',true), ('sales','sale_date','desc',true),
    ('loyalty_adjustments','adjustment_date','desc',true),
    ('sale_payments','payment_date','desc',true),
    ('customer_credits','credit_date','desc',true),
    ('customer_favorites','created_at','desc',false),
    ('favorite_dismissals','created_at','desc',false),
    ('expenses','expense_date','desc',true),
    ('cash_advances','advance_date','desc',true),
    ('cash_advance_payments','payment_date','desc',true),
    ('product_reservations','created_at','desc',true)
  ) as tables(table_name, order_column, order_direction, filter_deleted)
  loop
    begin
      execute format(
        'select coalesce(jsonb_agg(to_jsonb(t) order by %I %s), ''[]''::jsonb) from public.%I t%s',
        spec.order_column, spec.order_direction, spec.table_name,
        case when spec.filter_deleted then ' where not t.is_deleted' else '' end
      ) into rows;
    exception when undefined_table then rows := '[]'::jsonb;
    end;
    result := result || jsonb_build_object(spec.table_name, rows);
  end loop;
  return result;
end;
$$;
revoke all on function public.get_app_snapshot() from public;
grant execute on function public.get_app_snapshot() to authenticated;
