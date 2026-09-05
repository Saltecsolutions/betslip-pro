begin;
create temporary table result_ids(k text,id uuid);
insert into result_ids values('expert',gen_random_uuid()),('won',gen_random_uuid()),('lost',gen_random_uuid()),('void',gen_random_uuid());
insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@test.invalid','{"full_name":"Settlement verification","requested_role":"tipster","age_confirmed":true}' from result_ids where k='expert';
update public.tipsters set verification_status='active' where user_id=(select id from result_ids where k='expert');
insert into public.policy_acceptances(user_id,document,version,locale) select id,d,case when d='seller' then '2026-09-05-v2' else '2026-09-05' end,'en' from result_ids cross join unnest(array['terms','privacy','adult','seller']) d where k='expert';
insert into public.predictions(id,tipster_id,title,sport,match_name,prediction_text,betslip_code,odds,price_tzs,match_date,status) select id,(select id from public.tipsters where user_id=(select id from result_ids where k='expert')),k,'Football','Secret teams','Secret selection','Secret code',2,2000,now()+interval '1 second','pending' from result_ids where k<>'expert';
insert into public.prediction_selections(prediction_id,event_id,market_key,selection,odds) select id,'fixture-'||id::text,'match_winner','home',2 from result_ids where k<>'expert';
update public.predictions set status='published',published_at=now() where id in(select id from result_ids where k<>'expert');
-- PostgreSQL now() is transaction-stable. Set fixture dates behind transaction time
-- with the guard temporarily disabled in this rolled-back, locked transaction only.
alter table public.predictions disable trigger guard_prediction_record;
update public.predictions set match_date=now()-interval '1 minute' where id in(select id from result_ids where k<>'expert');
alter table public.predictions enable trigger guard_prediction_record;
select public.ingest_selection_result(s.id,r.k::public.prediction_result,'provider-'||r.id::text) from public.prediction_selections s join result_ids r on r.id=s.prediction_id;
-- Replays must not generate a second settlement event.
select public.ingest_selection_result(s.id,r.k::public.prediction_result,'provider-'||r.id::text) from public.prediction_selections s join result_ids r on r.id=s.prediction_id;
do $$ declare e record;begin
 if (select count(*) from public.settlement_events where prediction_id in(select id from result_ids))<>3 then raise exception 'FAIL terminal settlement or idempotency';end if;
 if exists(select 1 from public.predictions p join result_ids r on r.id=p.id where p.result::text<>r.k or status<>'resulted') then raise exception 'FAIL aggregate result';end if;
 select * into e from public.tipster_performance() where id=(select id from public.tipsters where user_id=(select id from result_ids where k='expert'));
 if e.wins<>1 or e.losses<>1 or e.voids<>1 or e.roi<>0 or e.win_rate<>50 then raise exception 'FAIL verified performance calculation';end if;
end $$;
select 'PASS: automatic Won/Lost/Void settlement, provider replay idempotency, unit ROI and win rate' as verification;
rollback;
