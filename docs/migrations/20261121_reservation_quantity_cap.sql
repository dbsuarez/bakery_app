-- Reservations could be submitted (or later bumped up) for more than a
-- product actually has left - the client only had an HTML max= hint, which
-- enforces nothing server-side. Both submit_product_reservation and
-- update_my_reservation_quantity now reject a quantity above the product's
-- current remaining stock (same remainingQuantity math as
-- get_available_products: count_produced minus customer_sale and
-- internal_consumption, summed across all non-deleted batches).
-- Run this complete file in the Supabase SQL Editor.

create or replace function public._product_remaining_quantity(p_product_id uuid)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(sum(
    b.count_produced - coalesce(sold.qty, 0) - coalesce(used.qty, 0)
  ), 0)::integer
  from public.batches b
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
  where b.product_id = p_product_id and not b.is_deleted;
$$;
revoke all on function public._product_remaining_quantity(uuid) from public;

create or replace function public.submit_product_reservation(
  p_product_id uuid,
  p_customer_name text default null,
  p_customer_contact text default null,
  p_quantity integer default 1,
  p_note text default null,
  p_soa_token text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_title text;
  v_id uuid;
  v_remaining integer;
  v_customer_id uuid;
  v_customer_name text;
  v_customer_contact text;
  link_record public.customer_soa_links%rowtype;
  customer_record public.customers%rowtype;
begin
  select user_id, title into v_user_id, v_title
  from public.products
  where id = p_product_id and not is_deleted;

  if v_user_id is null then raise exception 'Product not found'; end if;
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Quantity must be at least 1';
  end if;

  v_remaining := public._product_remaining_quantity(p_product_id);
  if p_quantity > v_remaining then
    raise exception 'Only % left of "%"', v_remaining, v_title;
  end if;

  if p_soa_token is not null then
    if length(p_soa_token) <> 64 then raise exception 'Statement link is invalid'; end if;
    select * into link_record from public.customer_soa_links l
    where l.token_hash = extensions.digest(convert_to(p_soa_token, 'UTF8'), 'sha256')
      and l.enabled and l.user_id = v_user_id
    limit 1;
    if link_record.id is null then raise exception 'Statement link is invalid'; end if;

    select * into customer_record from public.customers c
    where c.id = link_record.customer_id and not c.is_deleted;
    if customer_record.id is null then raise exception 'Customer not found'; end if;

    v_customer_id := customer_record.id;
    v_customer_name := customer_record.name;
    v_customer_contact := case
      when p_customer_contact is not null and length(trim(p_customer_contact)) > 0
        then trim(p_customer_contact)
      else coalesce(customer_record.phone, 'No phone on file')
    end;
  else
    if p_customer_name is null or length(trim(p_customer_name)) = 0 then
      raise exception 'Name is required';
    end if;
    if p_customer_contact is null or length(trim(p_customer_contact)) = 0 then
      raise exception 'Contact is required';
    end if;
    v_customer_name := trim(p_customer_name);
    v_customer_contact := trim(p_customer_contact);
  end if;

  insert into public.product_reservations(
    user_id, product_id, product_title, customer_id, customer_name, customer_contact, quantity, note
  ) values (
    v_user_id, p_product_id, v_title, v_customer_id, v_customer_name, v_customer_contact, p_quantity,
    nullif(trim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  return v_id;
end;
$$;
revoke all on function public.submit_product_reservation(uuid, text, text, integer, text, text) from public;
grant execute on function public.submit_product_reservation(uuid, text, text, integer, text, text) to anon, authenticated;

create or replace function public.update_my_reservation_quantity(
  p_soa_token text, p_reservation_id uuid, p_quantity integer
) returns void language plpgsql security definer set search_path = public as $$
declare target public.product_reservations%rowtype; v_remaining integer;
begin
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Quantity must be at least 1';
  end if;
  target := public._resolve_my_reservation(p_soa_token, p_reservation_id);
  if target.status = 'cancelled' then
    raise exception 'This reservation was cancelled - make a new one instead';
  end if;
  if target.product_id is not null then
    v_remaining := public._product_remaining_quantity(target.product_id);
    if p_quantity > v_remaining then
      raise exception 'Only % left of "%"', v_remaining, target.product_title;
    end if;
  end if;
  update public.product_reservations set quantity = p_quantity where id = target.id;
end;
$$;
revoke all on function public.update_my_reservation_quantity(text, uuid, integer) from public;
grant execute on function public.update_my_reservation_quantity(text, uuid, integer) to anon, authenticated;
