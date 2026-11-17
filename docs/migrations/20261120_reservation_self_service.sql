-- Lets a customer manage their own reservations from the public products
-- page, when identified via their own SOA link (web/soa.html?soa=<token>):
-- see what they've reserved, change the quantity, or cancel it. Scoped
-- strictly to that customer's own rows (via customer_id set by
-- submit_product_reservation's p_soa_token path) - anonymous reservations
-- (customer_id null) are never listed or editable through these RPCs.
-- Run this complete file in the Supabase SQL Editor.

create or replace function public.get_my_reservations(p_soa_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  link_record public.customer_soa_links%rowtype;
  rows jsonb;
begin
  if p_soa_token is null or length(p_soa_token) <> 64 then
    raise exception 'Statement link is invalid';
  end if;
  select * into link_record from public.customer_soa_links l
  where l.token_hash = extensions.digest(convert_to(p_soa_token, 'UTF8'), 'sha256') and l.enabled
  limit 1;
  if link_record.id is null then raise exception 'Statement link is invalid'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'product_title', r.product_title,
    'quantity', r.quantity,
    'note', r.note,
    'status', r.status,
    'created_at', r.created_at
  ) order by r.created_at desc), '[]'::jsonb) into rows
  from public.product_reservations r
  where r.customer_id = link_record.customer_id
    and r.user_id = link_record.user_id
    and not r.is_deleted;

  return rows;
end;
$$;
revoke all on function public.get_my_reservations(text) from public;
grant execute on function public.get_my_reservations(text) to anon, authenticated;

-- Shared ownership check used by both mutation RPCs below.
create or replace function public._resolve_my_reservation(
  p_soa_token text, p_reservation_id uuid
) returns public.product_reservations
language plpgsql security definer set search_path = public as $$
declare
  link_record public.customer_soa_links%rowtype;
  reservation_record public.product_reservations%rowtype;
begin
  if p_soa_token is null or length(p_soa_token) <> 64 then
    raise exception 'Statement link is invalid';
  end if;
  select * into link_record from public.customer_soa_links l
  where l.token_hash = extensions.digest(convert_to(p_soa_token, 'UTF8'), 'sha256') and l.enabled
  limit 1;
  if link_record.id is null then raise exception 'Statement link is invalid'; end if;

  select * into reservation_record from public.product_reservations r
  where r.id = p_reservation_id
    and r.customer_id = link_record.customer_id
    and r.user_id = link_record.user_id
    and not r.is_deleted;
  if reservation_record.id is null then raise exception 'Reservation not found'; end if;

  return reservation_record;
end;
$$;
revoke all on function public._resolve_my_reservation(text, uuid) from public;

create or replace function public.update_my_reservation_quantity(
  p_soa_token text, p_reservation_id uuid, p_quantity integer
) returns void language plpgsql security definer set search_path = public as $$
declare target public.product_reservations%rowtype;
begin
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Quantity must be at least 1';
  end if;
  target := public._resolve_my_reservation(p_soa_token, p_reservation_id);
  if target.status = 'cancelled' then
    raise exception 'This reservation was cancelled - make a new one instead';
  end if;
  update public.product_reservations set quantity = p_quantity where id = target.id;
end;
$$;
revoke all on function public.update_my_reservation_quantity(text, uuid, integer) from public;
grant execute on function public.update_my_reservation_quantity(text, uuid, integer) to anon, authenticated;

create or replace function public.cancel_my_reservation(
  p_soa_token text, p_reservation_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare target public.product_reservations%rowtype;
begin
  target := public._resolve_my_reservation(p_soa_token, p_reservation_id);
  update public.product_reservations set status = 'cancelled' where id = target.id;
end;
$$;
revoke all on function public.cancel_my_reservation(text, uuid) from public;
grant execute on function public.cancel_my_reservation(text, uuid) to anon, authenticated;
