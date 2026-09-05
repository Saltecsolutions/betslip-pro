-- Prevent clients from directly selecting paid betslip code or full paid analysis.
-- They must use get_betslip_code() after a paid purchase.
revoke select on table public.predictions from anon, authenticated;

grant select (
  id, tipster_id, title, sport, league, match_name, odds,
  confidence_level, price_tzs, category, risk_level, match_date,
  status, result, published_at, created_at
) on table public.predictions to anon, authenticated;

-- Keep the owning tipster/admin able to retrieve protected content through a guarded RPC.
create or replace function public.get_prediction_protected_content(p_prediction_id uuid)
returns table(prediction_text text, betslip_code text)
language sql
security definer
set search_path = public
as $$
  select p.prediction_text, p.betslip_code
  from public.predictions p
  where p.id = p_prediction_id
    and (
      public.is_admin()
      or exists (select 1 from public.tipsters t where t.id = p.tipster_id and t.user_id = auth.uid())
      or exists (
        select 1 from public.purchases pu
        where pu.prediction_id = p.id
          and pu.user_id = auth.uid()
          and pu.payment_status = 'paid'
      )
    );
$$;

grant execute on function public.get_prediction_protected_content(uuid) to authenticated;
