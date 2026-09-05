begin;
alter table public.settlement_events add column settled_odds numeric check(settled_odds>=1);
drop function public.admin_settle_prediction(uuid,public.prediction_result,text);
create function public.admin_settle_prediction(p_prediction_id uuid,p_result public.prediction_result,p_evidence text,p_effective_odds numeric default null) returns void language plpgsql security definer set search_path='' as $$
declare p public.predictions;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_result='pending' or length(btrim(p_evidence))<10 then raise exception 'Result and evidence required'; end if;
 select * into p from public.predictions where id=p_prediction_id for update;
 if not found or p.status<>'published' or p.result<>'pending' or p.match_date>now() then raise exception 'Not eligible for settlement'; end if;
 if p_effective_odds is not null and (p_effective_odds<1 or p_effective_odds>p.odds) then raise exception 'Adjusted odds must be between 1 and published total odds'; end if;
 if p_result='won' and exists(select 1 from public.prediction_selections where prediction_id=p.id and result='void') and p_effective_odds is null then raise exception 'Adjusted settled odds required for partial void accumulator'; end if;
 insert into public.settlement_events(prediction_id,result,source,evidence,actor_user_id,settled_odds) values(p.id,p_result,'admin_review',p_evidence,auth.uid(),coalesce(p_effective_odds,p.odds));
 update public.predictions set result=p_result,status='resulted',settled_at=now() where id=p.id;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'prediction_settled','prediction',p.id::text,jsonb_build_object('result',p_result,'evidence',p_evidence,'settled_odds',coalesce(p_effective_odds,p.odds)));
end $$;
revoke all on function public.admin_settle_prediction(uuid,public.prediction_result,text,numeric) from public,anon,authenticated;
grant execute on function public.admin_settle_prediction(uuid,public.prediction_result,text,numeric) to authenticated;
create unique index refund_reference_unique on public.disputes(lower(btrim(refund_reference))) where status='refunded';
create or replace function public.create_purchase(p_prediction_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare p public.predictions; v_id uuid;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and status='active' and age_verified) then raise exception 'Active adult account required';end if;
 select pr.* into p from public.predictions pr join public.tipsters t on t.id=pr.tipster_id join public.profiles u on u.id=t.user_id where pr.id=p_prediction_id and pr.status='published' and pr.match_date>now() and t.verification_status='active' and u.status='active' for share of pr,t,u;
 if not found then raise exception 'Prediction unavailable';end if;
 if exists(select 1 from public.tipsters where id=p.tipster_id and user_id=auth.uid()) then raise exception 'Cannot buy your own prediction';end if;
 insert into public.purchases(user_id,prediction_id,tipster_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs) values(auth.uid(),p.id,p.tipster_id,p.price_tzs,0,0) on conflict(user_id,prediction_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.purchases where user_id=auth.uid() and prediction_id=p.id;end if;
 return v_id;
end $$;
-- Restrict new payment verifications and balance releases to active administrators.
create or replace function public.admin_verify_manual_payment(
  p_purchase_id uuid,
  p_processing_fee_tzs integer default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_tipster_user uuid;
  v_tipster_amount integer;
begin
  select role in ('admin','super_admin') and status='active' into v_is_admin
  from public.profiles where id = auth.uid();
  if coalesce(v_is_admin,false) = false then raise exception 'Admin only'; end if;

  select t.user_id, p.tipster_commission_tzs
    into v_tipster_user, v_tipster_amount
  from public.purchases p
  join public.tipsters t on t.id = p.tipster_id
  where p.id = p_purchase_id
    and p.payment_status = 'submitted'
  for update;

  if v_tipster_user is null then raise exception 'Purchase not found or not submitted'; end if;

  update public.purchases
  set payment_status = 'paid',
      processing_fee_tzs = greatest(p_processing_fee_tzs,0),
      payment_verified_at = now(),
      verified_by = auth.uid()
  where id = p_purchase_id;

  update public.wallets
  set pending_balance_tzs = pending_balance_tzs + v_tipster_amount,
      updated_at = now()
  where user_id = v_tipster_user;

  insert into public.ledger_entries(purchase_id,user_id,entry_type,amount_tzs,metadata)
  values
    (p_purchase_id,v_tipster_user,'tipster_pending_earning',v_tipster_amount,'{"status":"pending"}'::jsonb),
    (p_purchase_id,null,'platform_commission',(select platform_commission_tzs from public.purchases where id=p_purchase_id),'{}'::jsonb),
    (p_purchase_id,null,'payment_processing_fee',greatest(p_processing_fee_tzs,0),'{}'::jsonb);
end;
$$;
create or replace function public.make_tipster_earnings_available(p_tipster_user_id uuid, p_amount_tzs bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_is_admin boolean;
begin
  select role in ('admin','super_admin') and status='active' into v_is_admin from public.profiles where id = auth.uid();
  if coalesce(v_is_admin,false) = false then raise exception 'Admin only'; end if;
  if p_amount_tzs <= 0 then raise exception 'Amount must be positive'; end if;

  update public.wallets
  set pending_balance_tzs = pending_balance_tzs - p_amount_tzs,
      available_balance_tzs = available_balance_tzs + p_amount_tzs,
      updated_at = now()
  where user_id = p_tipster_user_id
    and pending_balance_tzs >= p_amount_tzs;

  if not found then raise exception 'Insufficient pending balance'; end if;
end;
$$;
create or replace function public.tipster_performance() returns table(id uuid,display_name text,bio text,profile_image_url text,verification_status public.account_status,created_at timestamptz,total_predictions bigint,settled bigint,wins bigint,losses bigint,voids bigint,win_rate numeric,roi numeric,profit numeric,settled_30d bigint,roi_30d numeric,streak bigint,followers bigint,sales_30d bigint) language sql security definer set search_path='' as $$
 select t.id,t.display_name,t.bio,t.profile_image_url,t.verification_status,t.created_at,
 count(p.id),count(p.id) filter(where p.result in ('won','lost')),count(p.id) filter(where p.result='won'),count(p.id) filter(where p.result='lost'),count(p.id) filter(where p.result='void'),
 round(100.0*count(p.id) filter(where p.result='won')/nullif(count(p.id) filter(where p.result in ('won','lost')),0),1),
 round(100*sum(case when p.result='won' then coalesce((select se.settled_odds from public.settlement_events se where se.prediction_id=p.id),p.odds)-1 when p.result='lost' then -1 else 0 end)/nullif(count(p.id) filter(where p.result in ('won','lost')),0),1),
 sum(case when p.result='won' then coalesce((select se.settled_odds from public.settlement_events se where se.prediction_id=p.id),p.odds)-1 when p.result='lost' then -1 else 0 end),
 count(p.id) filter(where p.result in ('won','lost') and p.settled_at>now()-interval '30 days'),
 round(100*sum(case when p.settled_at>now()-interval '30 days' and p.result='won' then coalesce((select se.settled_odds from public.settlement_events se where se.prediction_id=p.id),p.odds)-1 when p.settled_at>now()-interval '30 days' and p.result='lost' then -1 else 0 end)/nullif(count(p.id) filter(where p.result in ('won','lost') and p.settled_at>now()-interval '30 days'),0),1),
 (select count(*) from public.predictions q where q.tipster_id=t.id and q.result='won' and q.settled_at>coalesce((select max(r.settled_at) from public.predictions r where r.tipster_id=t.id and r.result='lost'),'-infinity'::timestamptz)),
 (select count(*) from public.tipster_follows f where f.tipster_id=t.id),
 (select count(*) from public.purchases pu where pu.tipster_id=t.id and pu.payment_status='paid' and pu.created_at>now()-interval '30 days')
 from public.tipsters t left join public.predictions p on p.tipster_id=t.id and p.status in ('published','resulted') where t.verification_status='active' group by t.id;
$$;
commit;
