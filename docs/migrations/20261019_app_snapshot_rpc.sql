-- Fetch all app read models in one request. SECURITY INVOKER is intentional:
-- the existing per-table RLS policies continue to restrict every subquery.
-- This migration is safe to run repeatedly.

create or replace function public.get_app_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  result jsonb := '{}'::jsonb;
  rows jsonb;
  spec record;
begin
  -- Dynamic SQL preserves compatibility with older installations that do
  -- not yet have every optional feature table. Those keys return [] while
  -- existing tables still use their normal grants and RLS policies.
  for spec in
    select * from (values
      ('products',              'title',           'asc',  true),
      ('customers',             'name',            'asc',  true),
      ('batches',               'batch_date',      'desc', true),
      ('sales',                 'sale_date',       'desc', true),
      ('loyalty_adjustments',   'adjustment_date', 'desc', true),
      ('sale_payments',         'payment_date',    'desc', true),
      ('customer_credits',      'credit_date',     'desc', true),
      ('customer_favorites',    'created_at',      'desc', false),
      ('favorite_dismissals',   'created_at',      'desc', false),
      ('expenses',              'expense_date',    'desc', true),
      ('cash_advances',         'advance_date',    'desc', true),
      ('cash_advance_payments', 'payment_date',    'desc', true)
    ) as tables(table_name, order_column, order_direction, filter_deleted)
  loop
    begin
      execute format(
        'select coalesce(jsonb_agg(to_jsonb(t) order by %I %s), ''[]''::jsonb) '
        'from public.%I t%s',
        spec.order_column,
        spec.order_direction,
        spec.table_name,
        case when spec.filter_deleted then ' where not t.is_deleted' else '' end
      ) into rows;
    exception
      when undefined_table then
        rows := '[]'::jsonb;
    end;
    result := result || jsonb_build_object(spec.table_name, rows);
  end loop;

  return result;
end;
$$;

revoke all on function public.get_app_snapshot() from public;
grant execute on function public.get_app_snapshot() to authenticated;
