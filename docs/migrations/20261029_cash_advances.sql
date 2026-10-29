-- Cash advances are customer debts that do not belong to a product or batch.
-- Run this complete file in the Supabase SQL Editor.

create table if not exists public.cash_advances (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete restrict,
  advance_date date not null default current_date,
  amount numeric(12,2) not null check (amount > 0),
  paid boolean not null default false,
  date_paid date,
  payment_method text,
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create table if not exists public.cash_advance_payments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cash_advance_id uuid not null references public.cash_advances(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  payment_date date not null default current_date,
  payment_method text,
  notes text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create index if not exists cash_advances_user_customer_idx
on public.cash_advances(user_id, customer_id);
create index if not exists cash_advance_payments_user_advance_idx
on public.cash_advance_payments(user_id, cash_advance_id);

alter table public.cash_advances enable row level security;
alter table public.cash_advance_payments enable row level security;

drop policy if exists cash_advances_owner_access on public.cash_advances;
create policy cash_advances_owner_access on public.cash_advances
for all to authenticated using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists cash_advance_payments_owner_access on public.cash_advance_payments;
create policy cash_advance_payments_owner_access on public.cash_advance_payments
for all to authenticated using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.cash_advances to authenticated;
grant select, insert, update, delete on public.cash_advance_payments to authenticated;

create or replace function public.validate_cash_advance_owner()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.user_id is distinct from auth.uid() or not exists (
    select 1 from public.customers c
    where c.id = new.customer_id and c.user_id = new.user_id and not c.is_deleted
  ) then raise exception 'Cash advance customer must belong to the current user'; end if;
  if tg_op = 'UPDATE' and new.amount < coalesce((
    select sum(p.amount) from public.cash_advance_payments p
    where p.cash_advance_id = old.id and not p.is_deleted
  ), 0) then
    raise exception 'Cash advance amount cannot be less than payments already recorded';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cash_advance_owner on public.cash_advances;
create trigger trg_cash_advance_owner before insert or update on public.cash_advances
for each row execute function public.validate_cash_advance_owner();

drop trigger if exists trg_cash_advances_updated_at on public.cash_advances;
create trigger trg_cash_advances_updated_at before update on public.cash_advances
for each row execute function public.set_updated_at();
drop trigger if exists trg_cash_advance_payments_updated_at on public.cash_advance_payments;
create trigger trg_cash_advance_payments_updated_at before update on public.cash_advance_payments
for each row execute function public.set_updated_at();

create or replace function public.record_cash_advance_payment(
  p_cash_advance_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text default null,
  p_notes text default null
) returns void language plpgsql security invoker set search_path = public as $$
declare
  target public.cash_advances%rowtype;
  already_paid numeric(12,2);
  new_total numeric(12,2);
begin
  if p_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
  select * into target from public.cash_advances
  where id = p_cash_advance_id and user_id = auth.uid() and not is_deleted
  for update;
  if target.id is null then raise exception 'Cash advance not found'; end if;
  select coalesce(sum(amount), 0) into already_paid
  from public.cash_advance_payments
  where cash_advance_id = target.id and user_id = auth.uid() and not is_deleted;
  new_total := already_paid + p_amount;
  if new_total > target.amount then raise exception 'Payment exceeds the remaining balance'; end if;
  insert into public.cash_advance_payments(
    user_id, cash_advance_id, amount, payment_date, payment_method, notes
  ) values (
    auth.uid(), target.id, p_amount, p_payment_date, p_payment_method, p_notes
  );
  if new_total >= target.amount then
    update public.cash_advances set
      paid = true, date_paid = p_payment_date, payment_method = p_payment_method
    where id = target.id;
  end if;
end;
$$;
revoke all on function public.record_cash_advance_payment(uuid,numeric,date,text,text) from public;
grant execute on function public.record_cash_advance_payment(uuid,numeric,date,text,text) to authenticated;

-- Add the two ledgers to the app's one-request snapshot.
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
    ('cash_advance_payments','payment_date','desc',true)
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

-- Extend the public read-only SOA with cash advances and payment dates.
create or replace function public.get_customer_soa(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  link_record public.customer_soa_links%rowtype;
  business_name text; enabled_slots jsonb; balance numeric(12,2);
  sale_rows jsonb; qr_rows jsonb;
begin
  if p_token is null or length(p_token) <> 64 then raise exception 'Statement link is invalid'; end if;
  select * into link_record from public.customer_soa_links l
  where l.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256') and l.enabled limit 1;
  if link_record.id is null then raise exception 'Statement link is invalid'; end if;
  update public.customer_soa_links set last_accessed_at = now() where id = link_record.id;
  select coalesce(nullif(u.raw_user_meta_data->>'business_name',''),'My Bakery'),
    coalesce(u.raw_user_meta_data->'enabled_qr_slots','[1,2,3]'::jsonb)
  into business_name, enabled_slots from auth.users u where u.id = link_record.user_id;

  select coalesce(sum(remaining),0) into balance from (
    select greatest(s.amount-coalesce((select sum(sp.amount) from public.sale_payments sp
      where sp.sale_id=s.id and not sp.is_deleted),0),0) remaining
    from public.sales s where s.user_id=link_record.user_id and s.customer_id=link_record.customer_id
      and s.sale_type='customer_sale' and not s.is_deleted and not s.paid
    union all
    select greatest(a.amount-coalesce((select sum(ap.amount) from public.cash_advance_payments ap
      where ap.cash_advance_id=a.id and not ap.is_deleted),0),0)
    from public.cash_advances a where a.user_id=link_record.user_id and a.customer_id=link_record.customer_id
      and not a.is_deleted and not a.paid
  ) debt;

  select coalesce(jsonb_agg(row_data order by item_date desc), '[]'::jsonb) into sale_rows from (
    select s.sale_date item_date, jsonb_build_object(
      'id',s.id,'kind','sale','sale_date',s.sale_date,'product',p.title,'quantity',s.quantity,
      'amount',s.amount,'paid',s.paid,'date_paid',s.date_paid,'payment_method',s.payment_method,
      'remaining',case when s.paid then 0 else greatest(s.amount-coalesce((select sum(sp.amount)
        from public.sale_payments sp where sp.sale_id=s.id and not sp.is_deleted),0),0) end,
      'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',sp.amount,'date',sp.payment_date,
        'method',sp.payment_method) order by sp.payment_date) from public.sale_payments sp
        where sp.sale_id=s.id and not sp.is_deleted),'[]'::jsonb)
    ) row_data from public.sales s join public.batches b on b.id=s.batch_id
      join public.products p on p.id=b.product_id
    where s.user_id=link_record.user_id and s.customer_id=link_record.customer_id
      and s.sale_type='customer_sale' and not s.is_deleted
    union all
    select a.advance_date, jsonb_build_object(
      'id',a.id,'kind','cash_advance','sale_date',a.advance_date,'product','Cash advance','quantity',null,
      'amount',a.amount,'paid',a.paid,'date_paid',a.date_paid,'payment_method',a.payment_method,'notes',a.notes,
      'remaining',case when a.paid then 0 else greatest(a.amount-coalesce((select sum(ap.amount)
        from public.cash_advance_payments ap where ap.cash_advance_id=a.id and not ap.is_deleted),0),0) end,
      'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',ap.amount,'date',ap.payment_date,
        'method',ap.payment_method) order by ap.payment_date) from public.cash_advance_payments ap
        where ap.cash_advance_id=a.id and not ap.is_deleted),'[]'::jsonb)
    ) from public.cash_advances a where a.user_id=link_record.user_id
      and a.customer_id=link_record.customer_id and not a.is_deleted
  ) all_rows;

  select coalesce(jsonb_agg(o.name order by o.name),'[]'::jsonb) into qr_rows from storage.objects o
  where o.bucket_id='qr-codes' and o.name ~ ('^'||link_record.user_id::text||'/qr_[1-3][.][A-Za-z0-9]+$')
    and exists(select 1 from jsonb_array_elements_text(enabled_slots) slot(value)
      where slot.value=substring(o.name from 'qr_([0-9]+)[.]'));
  return jsonb_build_object('business_name',business_name,'generated_at',now(),
    'customer',(select jsonb_build_object('name',c.name) from public.customers c where c.id=link_record.customer_id),
    'balance',balance,'sales',sale_rows,'qr_paths',qr_rows);
end;
$$;
revoke all on function public.get_customer_soa(text) from public;
grant execute on function public.get_customer_soa(text) to anon, authenticated;

-- Restore the two new ledgers after the existing version-2 restore finishes.
-- Older v2 backups are accepted and simply contain empty lists here.
create or replace function public.restore_cash_advances_from_backup(p_backup jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare r jsonb; customer_uuid uuid; advance_uuid uuid;
begin
  for r in select value from jsonb_array_elements(coalesce(p_backup->'cash_advances','[]'::jsonb)) loop
    select (c->>'remote_id')::uuid into customer_uuid
    from jsonb_array_elements(p_backup->'customers') c
    where (c->>'id')::integer=(r->>'customer_id')::integer;
    insert into public.cash_advances(
      id,user_id,customer_id,advance_date,amount,paid,date_paid,payment_method,notes,updated_at,is_deleted
    ) values (
      (r->>'remote_id')::uuid,auth.uid(),customer_uuid,(r->>'advance_date')::date,
      (r->>'amount')::numeric,coalesce((r->>'paid')::boolean,false),
      nullif(r->>'date_paid','')::date,r->>'payment_method',r->>'notes',
      (r->>'updated_at')::timestamptz,false
    ) on conflict(id) do update set
      customer_id=excluded.customer_id,advance_date=excluded.advance_date,amount=excluded.amount,
      paid=excluded.paid,date_paid=excluded.date_paid,payment_method=excluded.payment_method,
      notes=excluded.notes,updated_at=excluded.updated_at,is_deleted=false
    where cash_advances.user_id=auth.uid();
  end loop;
  for r in select value from jsonb_array_elements(coalesce(p_backup->'cash_advance_payments','[]'::jsonb)) loop
    select (a->>'remote_id')::uuid into advance_uuid
    from jsonb_array_elements(p_backup->'cash_advances') a
    where (a->>'id')::integer=(r->>'cash_advance_id')::integer;
    insert into public.cash_advance_payments(
      id,user_id,cash_advance_id,amount,payment_date,payment_method,notes,updated_at,is_deleted
    ) values (
      (r->>'remote_id')::uuid,auth.uid(),advance_uuid,(r->>'amount')::numeric,
      (r->>'payment_date')::date,r->>'payment_method',r->>'notes',
      (r->>'updated_at')::timestamptz,false
    ) on conflict(id) do update set
      cash_advance_id=excluded.cash_advance_id,amount=excluded.amount,
      payment_date=excluded.payment_date,payment_method=excluded.payment_method,
      notes=excluded.notes,updated_at=excluded.updated_at,is_deleted=false
    where cash_advance_payments.user_id=auth.uid();
  end loop;
end;
$$;
revoke all on function public.restore_cash_advances_from_backup(jsonb) from public;
grant execute on function public.restore_cash_advances_from_backup(jsonb) to authenticated;
