-- Atomic inventory allocation for existing Bakery Tracker databases.
-- Safe to rerun: functions are replaced and grants are reapplied.

create or replace function public.create_sale_atomic(
  p_batch_id uuid,
  p_customer_id uuid,
  p_sale_date date,
  p_quantity integer,
  p_amount numeric,
  p_discount numeric default 0,
  p_paid boolean default false,
  p_date_paid date default null,
  p_payment_method text default null,
  p_sale_type text default 'customer_sale',
  p_notes text default null,
  p_is_reservation boolean default false,
  p_allow_overallocate boolean default false
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  target_batch public.batches%rowtype;
  allocated integer;
  new_id uuid;
begin
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select * into target_batch
  from public.batches
  where id = p_batch_id and user_id = auth.uid() and not is_deleted
  for update;
  if not found then raise exception 'Batch not found'; end if;

  if p_sale_type = 'customer_sale' and target_batch.locked then
    raise exception 'Cannot add a customer sale to a locked batch';
  end if;

  if p_sale_type in ('customer_sale', 'internal_consumption', 'points_redemption') then
    select coalesce(sum(quantity), 0)::integer into allocated
    from public.sales
    where batch_id = p_batch_id
      and user_id = auth.uid()
      and not is_deleted
      and sale_type in ('customer_sale', 'internal_consumption', 'points_redemption');
    if not p_allow_overallocate and allocated + p_quantity > target_batch.count_produced then
      raise exception 'Only % unit(s) remain in this batch', greatest(target_batch.count_produced - allocated, 0)
        using errcode = 'P0001';
    end if;
  end if;

  insert into public.sales(
    user_id, batch_id, customer_id, sale_date, quantity, amount, discount,
    paid, date_paid, payment_method, sale_type, notes, is_reservation
  ) values (
    auth.uid(), p_batch_id, p_customer_id, p_sale_date, p_quantity, p_amount,
    p_discount, p_paid, p_date_paid, p_payment_method, p_sale_type, p_notes,
    p_is_reservation
  ) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.create_batch_sales_atomic(
  p_batch_id uuid,
  p_entries jsonb,
  p_allow_overallocate boolean default false
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  target_batch public.batches%rowtype;
  allocated integer;
  requested integer;
  entry jsonb;
  inserted_count integer := 0;
begin
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'At least one transaction is required';
  end if;

  select * into target_batch
  from public.batches
  where id = p_batch_id and user_id = auth.uid() and not is_deleted
  for update;
  if not found then raise exception 'Batch not found'; end if;
  if target_batch.locked then
    raise exception 'Cannot add transactions to a locked batch';
  end if;

  select coalesce(sum((value->>'quantity')::integer), 0)::integer
  into requested from jsonb_array_elements(p_entries);
  if requested <= 0 or exists (
    select 1 from jsonb_array_elements(p_entries) where (value->>'quantity')::integer <= 0
  ) then
    raise exception 'Every quantity must be positive';
  end if;

  select coalesce(sum(quantity), 0)::integer into allocated
  from public.sales
  where batch_id = p_batch_id
    and user_id = auth.uid()
    and not is_deleted
    and sale_type in ('customer_sale', 'internal_consumption', 'points_redemption');
  if not p_allow_overallocate and allocated + requested > target_batch.count_produced then
    raise exception 'Only % unit(s) remain in this batch', greatest(target_batch.count_produced - allocated, 0)
      using errcode = 'P0001';
  end if;

  for entry in select value from jsonb_array_elements(p_entries) loop
    insert into public.sales(
      user_id, batch_id, customer_id, sale_date, quantity, amount, discount,
      paid, date_paid, payment_method, sale_type, notes, is_reservation
    ) values (
      auth.uid(), p_batch_id, (entry->>'customer_id')::uuid,
      (entry->>'sale_date')::date, (entry->>'quantity')::integer,
      (entry->>'amount')::numeric, coalesce((entry->>'discount')::numeric, 0),
      coalesce((entry->>'paid')::boolean, false), (entry->>'date_paid')::date,
      entry->>'payment_method', 'customer_sale', entry->>'notes',
      coalesce((entry->>'is_reservation')::boolean, false)
    );
    inserted_count := inserted_count + 1;
  end loop;
  return inserted_count;
end;
$$;

create or replace function public.update_sale_atomic(
  p_sale_id uuid,
  p_batch_id uuid,
  p_customer_id uuid,
  p_sale_date date,
  p_quantity integer,
  p_amount numeric,
  p_discount numeric default 0,
  p_paid boolean default false,
  p_date_paid date default null,
  p_payment_method text default null,
  p_sale_type text default 'customer_sale',
  p_notes text default null,
  p_is_reservation boolean default false,
  p_allow_overallocate boolean default false
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_sale public.sales%rowtype;
  target_batch public.batches%rowtype;
  allocated integer;
begin
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select * into current_sale from public.sales
  where id = p_sale_id and user_id = auth.uid() and not is_deleted;
  if not found then raise exception 'Transaction not found'; end if;

  perform 1 from public.batches
  where id in (current_sale.batch_id, p_batch_id) and user_id = auth.uid()
  order by id for update;

  if exists (
    select 1 from public.batches
    where id = current_sale.batch_id and locked
  ) then
    raise exception 'Transactions in a locked batch cannot be changed. Unlock the batch first.';
  end if;

  select * into target_batch from public.batches
  where id = p_batch_id and user_id = auth.uid() and not is_deleted;
  if not found then raise exception 'Batch not found'; end if;
  if p_sale_type = 'customer_sale' and target_batch.locked then
    raise exception 'Transactions cannot be moved into a locked batch';
  end if;

  if p_sale_type in ('customer_sale', 'internal_consumption', 'points_redemption') then
    select coalesce(sum(quantity), 0)::integer into allocated
    from public.sales
    where batch_id = p_batch_id
      and user_id = auth.uid()
      and id <> p_sale_id
      and not is_deleted
      and sale_type in ('customer_sale', 'internal_consumption', 'points_redemption');
    if not p_allow_overallocate and allocated + p_quantity > target_batch.count_produced then
      raise exception 'Only % unit(s) remain in this batch', greatest(target_batch.count_produced - allocated, 0)
        using errcode = 'P0001';
    end if;
  end if;

  update public.sales set
    batch_id = p_batch_id, customer_id = p_customer_id,
    sale_date = p_sale_date, quantity = p_quantity, amount = p_amount,
    discount = p_discount, paid = p_paid, date_paid = p_date_paid,
    payment_method = p_payment_method, sale_type = p_sale_type,
    notes = p_notes, is_reservation = p_is_reservation
  where id = p_sale_id and user_id = auth.uid();
end;
$$;

revoke all on function public.create_sale_atomic(uuid, uuid, date, integer, numeric, numeric, boolean, date, text, text, text, boolean, boolean) from public;
revoke all on function public.create_batch_sales_atomic(uuid, jsonb, boolean) from public;
revoke all on function public.update_sale_atomic(uuid, uuid, uuid, date, integer, numeric, numeric, boolean, date, text, text, text, boolean, boolean) from public;
grant execute on function public.create_sale_atomic(uuid, uuid, date, integer, numeric, numeric, boolean, date, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.create_batch_sales_atomic(uuid, jsonb, boolean) to authenticated;
grant execute on function public.update_sale_atomic(uuid, uuid, uuid, date, integer, numeric, numeric, boolean, date, text, text, text, boolean, boolean) to authenticated;
