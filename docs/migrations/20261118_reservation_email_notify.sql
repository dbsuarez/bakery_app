-- Emails the owner whenever a new public.product_reservations row is
-- inserted (a lead from the public announce/reserve page). Postgres can't
-- send email itself, so this uses pg_net to fire-and-forget an async HTTP
-- call to the notify-reservation Edge Function (supabase/functions/
-- notify-reservation), which sends the actual email via Resend.
--
-- Prerequisite: deploy the Edge Function first and set its secrets -
--   supabase functions deploy notify-reservation --no-verify-jwt
--   supabase secrets set RESEND_API_KEY=<your resend.com API key>
--   supabase secrets set NOTIFY_TO_EMAIL=<where alerts should go>
--   supabase secrets set TRIGGER_SECRET=b83f1d6c5ae97fc3ba7216e31f4685c628eb706ff60d7aad
-- The TRIGGER_SECRET value above must match exactly - it's what stops
-- anyone else from hitting the function and spamming fake reservation
-- emails; it is not the Resend key itself, so committing it here is low
-- stakes, but rotate it (regenerate, update both sides) if it ever looks
-- like it leaked.
--
-- Run this complete file in the Supabase SQL Editor, after the Edge
-- Function above is deployed and its secrets are set (a trigger that
-- fires before the function exists just logs a failed delivery in pg_net's
-- own log table - harmless, but the email won't send until both sides
-- are in place).

create extension if not exists pg_net;

create or replace function public.notify_reservation_created()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://okbcyeamtrgjhspiwwim.supabase.co/functions/v1/notify-reservation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-trigger-secret', 'b83f1d6c5ae97fc3ba7216e31f4685c628eb706ff60d7aad'
    ),
    body := jsonb_build_object(
      'product_title', new.product_title,
      'customer_name', new.customer_name,
      'customer_contact', new.customer_contact,
      'quantity', new.quantity,
      'note', new.note
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_reservation_created on public.product_reservations;
create trigger trg_notify_reservation_created
after insert on public.product_reservations
for each row execute function public.notify_reservation_created();
