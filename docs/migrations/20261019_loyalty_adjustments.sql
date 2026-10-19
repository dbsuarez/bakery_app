-- Adds manual loyalty adjustments to older installations.
-- Safe to run repeatedly.

create extension if not exists "uuid-ossp";

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
  constraint loyalty_adjustments_category_valid
    check (category in ('bakery', 'merchandise')),
  constraint loyalty_adjustments_points_nonzero check (points <> 0)
);

create index if not exists loyalty_adjustments_user_id_idx
  on public.loyalty_adjustments(user_id);
create index if not exists loyalty_adjustments_customer_id_idx
  on public.loyalty_adjustments(customer_id);
create index if not exists loyalty_adjustments_updated_at_idx
  on public.loyalty_adjustments(updated_at);

create or replace function public.validate_loyalty_adjustment_owner()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.customers
    where id = new.customer_id and user_id = new.user_id
  ) then
    raise exception 'Customer does not belong to the same user';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_loyalty_adjustments_owner_relationship
  on public.loyalty_adjustments;
create trigger trg_loyalty_adjustments_owner_relationship
before insert or update on public.loyalty_adjustments
for each row execute function public.validate_loyalty_adjustment_owner();

drop trigger if exists trg_loyalty_adjustments_updated_at
  on public.loyalty_adjustments;
create trigger trg_loyalty_adjustments_updated_at
before update on public.loyalty_adjustments
for each row execute function public.set_updated_at();

alter table public.loyalty_adjustments enable row level security;
drop policy if exists loyalty_adjustments_owner_access
  on public.loyalty_adjustments;
create policy loyalty_adjustments_owner_access
on public.loyalty_adjustments for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update, delete on public.loyalty_adjustments
  to authenticated;
