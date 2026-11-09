-- Remove the old three-slot limit from public customer SOAs. Payment QR
-- objects remain ordered by their numeric slot, including slot 10 and above.

create or replace function public.get_customer_soa(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  link_record public.customer_soa_links%rowtype;
  business_name text; enabled_slots jsonb; qr_label_map jsonb; balance numeric(12,2);
  sale_rows jsonb; qr_rows jsonb; qr_label_rows jsonb;
begin
  if p_token is null or length(p_token) <> 64 then raise exception 'Statement link is invalid'; end if;
  select * into link_record from public.customer_soa_links l
  where l.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256') and l.enabled limit 1;
  if link_record.id is null then raise exception 'Statement link is invalid'; end if;
  update public.customer_soa_links set last_accessed_at = now() where id = link_record.id;
  select coalesce(nullif(u.raw_user_meta_data->>'business_name',''),'My Bakery'),
    coalesce(u.raw_user_meta_data->'enabled_qr_slots','[1,2,3]'::jsonb),
    coalesce(u.raw_user_meta_data->'qr_labels','{}'::jsonb)
  into business_name, enabled_slots, qr_label_map
  from auth.users u where u.id = link_record.user_id;

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

  select
    coalesce(jsonb_agg(q.name order by q.slot_number), '[]'::jsonb),
    coalesce(jsonb_agg(
      coalesce(qr_label_map->>q.slot_number::text, 'Payment QR '||q.slot_number)
      order by q.slot_number
    ), '[]'::jsonb)
  into qr_rows, qr_label_rows
  from (
    select o.name, (substring(o.name from '/qr_([0-9]+)[.]'))::int slot_number
    from storage.objects o
    where o.bucket_id='qr-codes'
      and o.name ~ ('^'||link_record.user_id::text||'/qr_[0-9]+[.][A-Za-z0-9]+$')
      and exists(select 1 from jsonb_array_elements_text(enabled_slots) slot(value)
        where slot.value=substring(o.name from 'qr_([0-9]+)[.]'))
  ) q;

  return jsonb_build_object('business_name',business_name,'generated_at',now(),
    'customer',(select jsonb_build_object('name',c.name) from public.customers c where c.id=link_record.customer_id),
    'balance',balance,'sales',sale_rows,'qr_paths',qr_rows,'qr_labels',qr_label_rows);
end;
$$;

revoke all on function public.get_customer_soa(text) from public;
grant execute on function public.get_customer_soa(text) to anon, authenticated;
