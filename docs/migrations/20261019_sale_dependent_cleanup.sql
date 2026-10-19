-- Keeps dependent financial rows consistent when a sale is soft-deleted.
-- Payments are also soft-deleted; credits remain active but are detached
-- because a customer credit is an independent ledger entry.
-- Safe to run repeatedly.

-- Preserve remittance protection while allowing the cleanup operation for a
-- payment whose parent sale is already soft-deleted. This also lets the
-- one-time repair below handle an old orphan in a subsequently remitted batch.
create or replace function public.prevent_remitted_payment_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  target_sale_id uuid;
begin
  if tg_op = 'UPDATE'
     and new.is_deleted
     and not old.is_deleted
     and exists (
       select 1 from public.sales
       where id = old.sale_id and is_deleted
     ) then
    return new;
  end if;

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
      and (b.locked or b.remitted)
  ) then
    raise exception 'Payments in a remitted batch cannot be changed. Reopen the remittance first.'
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.cleanup_soft_deleted_sale_dependents()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.is_deleted and not old.is_deleted then
    update public.sale_payments
    set is_deleted = true
    where sale_id = new.id and not is_deleted;

    update public.customer_credits
    set sale_id = null
    where sale_id = new.id and not is_deleted;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cleanup_soft_deleted_sale_dependents
  on public.sales;
create trigger trg_cleanup_soft_deleted_sale_dependents
after update of is_deleted on public.sales
for each row
when (new.is_deleted and not old.is_deleted)
execute function public.cleanup_soft_deleted_sale_dependents();

-- Repair rows created before the trigger existed.
update public.sale_payments p
set is_deleted = true
from public.sales s
where p.sale_id = s.id
  and s.is_deleted
  and not p.is_deleted;

update public.customer_credits c
set sale_id = null
from public.sales s
where c.sale_id = s.id
  and s.is_deleted
  and not c.is_deleted;
