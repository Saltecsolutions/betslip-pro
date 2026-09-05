begin;
create temporary table level_ids(k text primary key,id uuid);
insert into level_ids values('expert',gen_random_uuid()),('buyer',gen_random_uuid());
insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@test.invalid',jsonb_build_object('full_name','Level test','requested_role',case when k='expert' then 'tipster' else 'bettor' end,'age_confirmed',true) from level_ids;
update public.tipsters set verification_status='active' where user_id=(select id from level_ids where k='expert');
-- Isolated historical fixtures, all rolled back. No test picks become visible.
alter table public.predictions disable trigger guard_prediction_record;
insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,betslip_code,odds,price_tzs,match_date,status,published_at,result,settled_at)
select (select id from public.tipsters where user_id=(select id from level_ids where k='expert')),'Level fixture '||n,'Football','Fixture','Fixture','Fixture',2,2000,now()-interval '2 days','resulted',now()-interval '3 days',case when n%4=0 then 'lost'::public.prediction_result else 'won'::public.prediction_result end,now()-interval '1 day' from generate_series(1,20) n;
alter table public.predictions enable trigger guard_prediction_record;
do $$ declare tid uuid;begin
 select id into tid from public.tipsters where user_id=(select id from level_ids where k='expert');
 if not exists(select 1 from jsonb_array_elements(public.expert_insights()) e where e->>'id'=tid::text and e->>'level'='Verified') then raise exception 'FAIL Verified threshold';end if;
end $$;
alter table public.predictions disable trigger guard_prediction_record;
insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,betslip_code,odds,price_tzs,match_date,status,published_at,result,settled_at)
select (select id from public.tipsters where user_id=(select id from level_ids where k='expert')),'Level fixture '||n,'Football','Fixture','Fixture','Fixture',2,2000,now()-interval '2 days','resulted',now()-interval '3 days',case when n%4=0 then 'lost'::public.prediction_result else 'won'::public.prediction_result end,now()-interval '1 day' from generate_series(21,75) n;
alter table public.predictions enable trigger guard_prediction_record;
insert into public.purchases(user_id,prediction_id,tipster_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_status) select (select id from level_ids where k='buyer'),id,tipster_id,2000,600,1400,'paid' from public.predictions where tipster_id=(select id from public.tipsters where user_id=(select id from level_ids where k='expert')) limit 20;
insert into public.purchase_ratings(purchase_id,user_id,rating) select id,user_id,5 from public.purchases where user_id=(select id from level_ids where k='buyer');
do $$ declare tid uuid;begin
 select id into tid from public.tipsters where user_id=(select id from level_ids where k='expert');
 if not exists(select 1 from jsonb_array_elements(public.expert_insights()) e where e->>'id'=tid::text and e->>'level'='Pro') then raise exception 'FAIL Pro threshold';end if;
end $$;
alter table public.predictions disable trigger guard_prediction_record;
insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,betslip_code,odds,price_tzs,match_date,status,published_at,result,settled_at)
select (select id from public.tipsters where user_id=(select id from level_ids where k='expert')),'Level fixture '||n,'Football','Fixture','Fixture','Fixture',2,2000,now()-interval '2 days','resulted',now()-interval '3 days',case when n%4=0 then 'lost'::public.prediction_result else 'won'::public.prediction_result end,now()-interval '1 day' from generate_series(76,200) n;
alter table public.predictions enable trigger guard_prediction_record;
do $$ declare tid uuid;begin
 select id into tid from public.tipsters where user_id=(select id from level_ids where k='expert');
 if not exists(select 1 from jsonb_array_elements(public.expert_insights()) e where e->>'id'=tid::text and e->>'level'='Elite') then raise exception 'FAIL Elite threshold';end if;
end $$;
select 'PASS: Verified, Pro, Elite sample/performance/rating thresholds' as verification;
rollback;
