-- Creates the payment QR storage bucket and owner-scoped write policies.
-- Safe to run as a whole more than once.

insert into storage.buckets (id, name, public)
values ('qr-codes', 'qr-codes', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists qr_codes_public_read on storage.objects;
create policy qr_codes_public_read
on storage.objects for select
using (bucket_id = 'qr-codes');

drop policy if exists qr_codes_owner_insert on storage.objects;
create policy qr_codes_owner_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists qr_codes_owner_update on storage.objects;
create policy qr_codes_owner_update
on storage.objects for update to authenticated
using (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists qr_codes_owner_delete on storage.objects;
create policy qr_codes_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);
