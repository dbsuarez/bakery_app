-- Lets a customer reserve a product straight from their own SOA link
-- (web/soa.html?soa=<token>) without retyping their name: the reservation
-- form on web/products.html carries that same token through, and this RPC
-- resolves the customer from it instead of trusting a free-typed name.
-- Anonymous visitors (no token, arriving at products.html directly) still
-- type their own name and contact, exactly as before.
-- Run this complete file in the Supabase SQL Editor.

alter table public.product_reservations
  add column if not exists customer_id uuid references public.customers(id) on delete set null;

drop function if exists public.submit_product_reservation(uuid, text, text, integer, text);

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

    -- The identity (name) is trusted from the private link, not the
    -- request body - a visitor with a stranger's leaked link still
    -- can't reserve under a different name. Contact stays editable
    -- (defaulting to the phone on file) in case it's stale.
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
