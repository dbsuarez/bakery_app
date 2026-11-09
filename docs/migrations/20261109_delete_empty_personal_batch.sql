-- Safely remove a mistakenly-created Personal batch without touching its
-- reusable product. Only the owner may delete an unremitted Personal batch,
-- and only when it has no live transactions.

create or replace function public.delete_empty_personal_batch(p_batch_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_batch public.batches%rowtype;
begin
  select *
    into v_batch
    from public.batches
   where id = p_batch_id
     and user_id = auth.uid()
     and not is_deleted
   for update;

  if not found then
    raise exception 'Batch not found.' using errcode = 'P0002';
  end if;

  if not v_batch.is_personal then
    raise exception 'Only Personal batches can be deleted here.' using errcode = 'P0001';
  end if;

  if v_batch.remitted then
    raise exception 'A remitted batch cannot be deleted.' using errcode = 'P0001';
  end if;

  if exists (
    select 1
      from public.sales
     where batch_id = p_batch_id
       and user_id = auth.uid()
       and not is_deleted
  ) then
    raise exception 'This batch has transactions and cannot be deleted.' using errcode = 'P0001';
  end if;

  update public.batches
     set is_deleted = true,
         updated_at = now()
   where id = p_batch_id
     and user_id = auth.uid();
end;
$$;

revoke all on function public.delete_empty_personal_batch(uuid) from public;
grant execute on function public.delete_empty_personal_batch(uuid) to authenticated;
