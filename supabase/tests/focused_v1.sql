begin;
create temporary table focused_ids(k text primary key,id uuid);
insert into focused_ids values('expert',gen_random_uuid()),('buyer',gen_random_uuid()),('stranger',gen_random_uuid()),('admin',gen_random_uuid()),('p',gen_random_uuid());
insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@test.invalid',jsonb_build_object('full_name','Focused V1 test','requested_role',case when k='expert' then 'tipster' else 'bettor' end,'age_confirmed',true) from focused_ids where k<>'p';
update public.profiles set role='admin' where id=(select id from focused_ids where k='admin');
update public.tipsters set verification_status='active' where user_id=(select id from focused_ids where k='expert');
insert into public.policy_acceptances(user_id,document,version,locale) select id,d,'2026-09-05','en' from focused_ids cross join unnest(array['terms','privacy','adult','seller']) d where k<>'p';
insert into compliance.staff_access(user_id,finance) select id,true from focused_ids where k='admin';
insert into public.predictions(id,tipster_id,title,sport,match_name,prediction_text,betslip_code,odds,price_tzs,match_date,status,analysis,confidence) values((select id from focused_ids where k='p'),(select id from public.tipsters where user_id=(select id from focused_ids where k='expert')),'Test preview','Football','SECRET TEAMS','SECRET PICKS','SECRET CODE',3,2000,now()+interval '1 day','pending','Short test analysis without protected selections.',65);
insert into public.prediction_selections(prediction_id,event_id,market_key,selection,odds) select id,'fixture','winner','home',3 from focused_ids where k='p';
update public.predictions set status='published',published_at='2000-01-01' where id=(select id from focused_ids where k='p');
do $$ begin
 if exists(select 1 from public.predictions where id=(select id from focused_ids where k='p') and published_at<now()-interval '1 minute') then raise exception 'FAIL forged publication timestamp';end if;
 if not exists(select 1 from public.audit_logs where entity_id=(select id::text from focused_ids where k='p') and action='prediction_published') then raise exception 'FAIL publication audit';end if;
 begin update public.prediction_selections set selection='away' where prediction_id=(select id from focused_ids where k='p');raise exception 'FAIL mapping edit';exception when others then if sqlerrm='FAIL mapping edit' then raise;end if;end;
 begin update public.predictions set confidence=99 where id=(select id from focused_ids where k='p');raise exception 'FAIL confidence edit';exception when others then if sqlerrm='FAIL confidence edit' then raise;end if;end;
 begin delete from public.audit_logs where entity_id=(select id::text from focused_ids where k='p');raise exception 'FAIL audit delete';exception when others then if sqlerrm='FAIL audit delete' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from focused_ids where k='buyer'),true);
select public.create_purchase((select id from focused_ids where k='p'));
select public.submit_manual_payment(id,'FOCUSED-'||id,null) from public.purchases where user_id=(select id from focused_ids where k='buyer');
select set_config('request.jwt.claim.sub',(select id::text from focused_ids where k='admin'),true);
select public.admin_verify_manual_payment(id,73) from public.purchases where user_id=(select id from focused_ids where k='buyer');
select set_config('request.jwt.claim.sub',(select id::text from focused_ids where k='buyer'),true);
grant select on focused_ids to authenticated;
set local role authenticated;
insert into public.purchase_ratings(purchase_id,user_id,rating) select id,user_id,4 from public.purchases where user_id=auth.uid();
reset role;
select set_config('request.jwt.claim.sub',(select id::text from focused_ids where k='stranger'),true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.purchase_ratings) then raise exception 'FAIL rating privacy';end if;
 begin insert into public.purchase_ratings(purchase_id,user_id,rating) values(gen_random_uuid(),auth.uid(),5);raise exception 'FAIL unpaid rating accepted';exception when insufficient_privilege then null;end;
 begin insert into public.tipster_reviews(tipster_id,on_hold,reason,reviewed_by) select id,true,'forged hold',auth.uid() from public.tipsters limit 1;raise exception 'FAIL review direct write';exception when insufficient_privilege then null;end;
 begin perform public.admin_review_tipster((select id from public.tipsters limit 1),true,'Forged review should fail');raise exception 'FAIL admin escalation';exception when others then if sqlerrm='FAIL admin escalation' then raise;end if;end;
 if has_function_privilege('authenticated','public.performance_window(uuid,integer)','execute') then raise exception 'FAIL internal metrics exposed';end if;
end $$;
reset role;
-- Only test fixtures are backdated, under a transactional table lock. No retained data.
alter table public.predictions disable trigger guard_prediction_record;
update public.predictions set match_date=now()-interval '1 hour' where id=(select id from focused_ids where k='p');
alter table public.predictions enable trigger guard_prediction_record;
select set_config('request.jwt.claim.sub',(select id::text from focused_ids where k='admin'),true);
select public.admin_settle_prediction((select id from focused_ids where k='p'),'won','Verified adjusted odds fixture',2);
do $$ declare m jsonb; tid uuid;begin
 select id into tid from public.tipsters where user_id=(select id from focused_ids where k='expert');
 m:=public.performance_window(tid,7);
 if (m->>'roi')::numeric<>100 or (m->>'profit')::numeric<>1 or (m->>'average_odds')::numeric<>3 or (m->>'settled')::int<>1 then raise exception 'FAIL effective odds/window metrics: %',m;end if;
 begin update public.settlement_events set settled_odds=99 where prediction_id=(select id from focused_ids where k='p');raise exception 'FAIL settlement edit';exception when others then if sqlerrm='FAIL settlement edit' then raise;end if;end;
 perform public.admin_review_tipster(tid,true,'Review hold test evidence');
 if not exists(select 1 from jsonb_array_elements(public.expert_insights()) e where e->>'id'=tid::text and e->>'compliant'='false' and e->>'level'='New') then raise exception 'FAIL compliance level';end if;
 perform set_config('request.jwt.claim.sub',(select id::text from focused_ids where k='expert'),true);
 m:=public.tipster_business_summary();
 if (m->>'platform')::int<>300 or (m->>'earnings')::int<>700 or (m->>'fees')::int<>73 or (m->>'conversion')::numeric<>100 or (m->>'rating')::numeric<>4 then raise exception 'FAIL business accounting: %',m;end if;
end $$;
-- Boundary fixture demonstrates settlement-time window inclusion.
alter table public.predictions disable trigger guard_prediction_record;
update public.predictions set settled_at=now()-interval '8 days' where id=(select id from focused_ids where k='p');
alter table public.predictions enable trigger guard_prediction_record;
do $$ declare tid uuid;begin
 select id into tid from public.tipsters where user_id=(select id from focused_ids where k='expert');
 if (public.performance_window(tid,7)->>'settled')::int<>0 or (public.performance_window(tid,30)->>'settled')::int<>1 then raise exception 'FAIL time windows';end if;
end $$;
select 'PASS: publication timestamp, audit/selection locks, effective odds, windows, compliance review, rating RLS, business conversion and fee separation' as verification;
rollback;
