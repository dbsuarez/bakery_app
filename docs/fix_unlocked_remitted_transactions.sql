-- Run once in the Supabase SQL Editor.
-- A remitted batch remains protected while locked. The app's Unlock action
-- clears only `locked`, allowing corrections without removing remittance
-- history or its remittance date.
-- Also run docs/migrations/20261019_atomic_inventory_writes.sql afterward;
-- the atomic save functions enforce the same rule independently.

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

create or replace function public.prevent_remitted_payment_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  target_sale_id uuid;
begin
  target_sale_id := case
    when tg_op = 'DELETE' then old.sale_id
    else new.sale_id
  end;

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
