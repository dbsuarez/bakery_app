-- Allow a sale's existing discount field to represent both manual adjustments:
--   positive = approved discount (reduces the amount to remit)
--   negative = customer-approved add-on (increases the amount to remit)
-- This retains compatibility with existing backups and RPC parameters.

alter table public.sales
  drop constraint if exists sales_discount_nonnegative;
