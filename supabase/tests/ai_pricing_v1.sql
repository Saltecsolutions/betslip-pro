begin;
create temp table ids(k text primary key,id uuid);
insert into ids values('seller',gen_random_uuid()),('buyer',gen_random_uuid()),('admin',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id||'@test.invalid',now(),'{}' from ids;
insert into public.policy_acceptances(user_id,document,version,locale) select id,d,'2026-09-05','en' from ids cross join unnest(array['terms','privacy','adult','seller']) d;
update public.profiles set role='super_admin' where id=(select id from ids where k='admin');
insert into public.tipsters(user_id,display_name,verification_status) select id,'Pricing test','active' from ids where k='seller';
insert into ids select 'tid',id from public.tipsters where user_id=(select id from ids where k='seller');
grant all on ids to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from ids where k='seller'),true);
set local role authenticated;
do $$declare p jsonb;r jsonb;begin
 p:=public.my_ai_price();if (p->>'price_tzs')::int<>1000 then raise exception 'FAIL starter price';end if;
 begin insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,match_date,price_tzs) values((select id from ids where k='tid'),'Bypass','Football','A vs B','Home wins',now()+interval '1 day',9000);raise exception 'FAIL direct submission';exception when insufficient_privilege then null;end;
 begin perform public.platform_revenue_summary();raise exception 'FAIL seller finance access';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 r:=public.submit_prediction(jsonb_build_object('title','First pricing fixture','sport','Football','match_name','A vs B','prediction_text','Home team wins','analysis','A complete preview for testing this submission.','match_date',now()+interval '1 day','odds',2,'selection_count',1,'bookmaker','BetPawa','betslip_code','TEST001','price_tzs',9000));
 if r->>'status'<>'pending' or not(r->'reasons'?'probation') then raise exception 'FAIL probation';end if;
 insert into ids values('first',(r->>'id')::uuid);
end $$;
reset role;
do $$begin if (select price_tzs from public.predictions where id=(select id from ids where k='first'))<>1000 then raise exception 'FAIL spoofed price';end if;end $$;
-- Twenty-five real publication + settlement records with 80% wins and positive unit ROI.
insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,match_date,odds,status,price_tzs)
select (select id from ids where k='tid'),'History '||g,'Football','Test A vs B','Home win',now()+interval '1 day',2,'pending',5000 from generate_series(1,25) g;
update public.predictions set status='published' where title like 'History %';
alter table public.predictions disable trigger guard_prediction_record;
update public.predictions set match_date=now()-interval '1 day' where title like 'History %';
alter table public.predictions enable trigger guard_prediction_record;
insert into public.settlement_events(prediction_id,result,source,evidence,settled_odds) select id,case when substring(title from 9)::int<=20 then 'won'::public.prediction_result else 'lost'::public.prediction_result end,'provider','test verified history',2 from public.predictions where title like 'History %';
update public.predictions p set result=s.result,status='resulted',settled_at=now() from public.settlement_events s where s.prediction_id=p.id;
insert into public.purchases(user_id,prediction_id,tipster_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_status,payment_verified_at)
select (select id from ids where k='buyer'),id,tipster_id,price_tzs,0,0,'paid',now() from public.predictions where title like 'History %';
do $$declare p engine.prices;s jsonb;begin
 s:=engine.signals((select id from ids where k='tid'));
 if (s->>'sample_size')::int<>25 or (s->>'win_rate')::numeric<>0.8 or (s->>'roi')::numeric<>0.6 then raise exception 'FAIL verified metrics %',s;end if;
 p:=engine.review_price((select id from ids where k='tid'));if p.price_tzs<>1000 then raise exception 'FAIL daily guard';end if;
 update engine.prices set reviewed_at=now()-interval '25 hours';
 p:=engine.review_price((select id from ids where k='tid'));if p.price_tzs<>1500 then raise exception 'FAIL upward one-band step %',p;end if;
 update engine.prices set reviewed_at=now()-interval '25 hours';
 p:=engine.review_price((select id from ids where k='tid'));if p.price_tzs<>1500 then raise exception 'FAIL 5-result guard';end if;
 if (select count(*) from engine.price_reviews)<>1 then raise exception 'FAIL idempotent review';end if;
 if exists(select 1 from public.predictions where title like 'History %' and price_tzs<>1000) then raise exception 'FAIL published prices changed';end if;
 begin update public.predictions set price_tzs=2000 where title='History 1';raise exception 'FAIL immutable price';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 -- Replay model with guardrails; hold forces a downward target while step cap still applies.
 if engine.target_price(s||'{"hold":true}')<>1000 or engine.target_price(s||'{"sample_size":2}')<>1000 or engine.target_price(s||'{"refund_rate":0.2}')<>1000 then raise exception 'FAIL model risk guards';end if;
 update engine.prices set decided_count=20,reviewed_at=now()-interval '25 hours';
 insert into public.tipster_reviews values((select id from ids where k='tid'),true,'Test integrity hold',(select id from ids where k='admin'),now());
 p:=engine.review_price((select id from ids where k='tid'));if p.price_tzs<>1000 then raise exception 'FAIL downward price';end if;
end $$;
-- Full-history revenue excludes submitted orders and never clips to the reader's 200 rows.
insert into public.purchases(user_id,prediction_id,tipster_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_status)
values((select id from ids where k='buyer'),(select id from ids where k='first'),(select id from ids where k='tid'),1000,0,0,'submitted');
select set_config('request.jwt.claim.sub',(select id::text from ids where k='admin'),true);
set local role authenticated;
do $$declare s jsonb;begin
 s:=public.platform_revenue_summary();if (s->>'gross')::int<>25000 or (s->>'tipster')::int<>17500 or (s->>'wht')::int<>1250 or (s->>'platformNet')::int<>6250 then raise exception 'FAIL revenue %',s;end if;
 perform public.configure_wht_allocation(600,'Test allocation policy change');
end $$;
reset role;
do $$begin if exists(select 1 from public.purchases where wht_bps<>500 or wht_allocation_tzs<>50 or platform_net_tzs<>250) then raise exception 'FAIL historical allocation changed';end if;end $$;
-- Reservation and processing are atomic; retry cannot debit a wallet twice.
update public.wallets set available_balance_tzs=2000 where user_id=(select id from ids where k='seller');
select set_config('request.jwt.claim.sub',(select id::text from ids where k='seller'),true);
set local role authenticated;
insert into ids values('request',gen_random_uuid());
insert into ids values('withdrawal',public.request_withdrawal(1500,'mobile_money','255700000000',(select id from ids where k='request')));
do $$begin if public.request_withdrawal(1500,'mobile_money','255700000000',(select id from ids where k='request'))<>(select id from ids where k='withdrawal') then raise exception 'FAIL request replay';end if;end $$;
do $$begin begin perform public.request_withdrawal(1500,'mobile_money','255700000000');raise exception 'FAIL overspend';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub',(select id::text from ids where k='admin'),true);
select public.finish_payout((select id from ids where k='withdrawal'),'paid','PAYOUT-TEST');
do $$begin begin perform public.finish_payout((select id from ids where k='withdrawal'),'paid','PAYOUT-TEST');raise exception 'FAIL payout replay';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;end $$;
reset role;
do $$begin if not exists(select 1 from public.wallets where user_id=(select id from ids where k='seller') and available_balance_tzs=500 and total_withdrawn_tzs=1500) then raise exception 'FAIL payout balance';end if;end $$;
select 'PASS pricing, cadence, audit, price enforcement, allocation, permissions and payout idempotency' result;
rollback;
