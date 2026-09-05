begin;
-- Transactional fixtures are never retained in the hosted database.
create temporary table v1_ids(k text primary key,id uuid);
insert into v1_ids values('buyer',gen_random_uuid()),('stranger',gen_random_uuid()),('expert',gen_random_uuid()),('admin',gen_random_uuid()),('prediction',gen_random_uuid());
insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@test.invalid',jsonb_build_object('full_name','V1 verification','requested_role',case when k='expert' then 'tipster' else 'bettor' end,'age_confirmed',true) from v1_ids where k<>'prediction';
update public.profiles set role='admin' where id=(select id from v1_ids where k='admin');
update public.tipsters set verification_status='active' where user_id=(select id from v1_ids where k='expert');
insert into public.predictions(id,tipster_id,title,sport,match_name,prediction_text,betslip_code,odds,price_tzs,match_date,status) values((select id from v1_ids where k='prediction'),(select id from public.tipsters where user_id=(select id from v1_ids where k='expert')),'V1 test','Football','SECRET TEAMS','SECRET SELECTION','SECRET CODE',2.5,2000,now()+interval '1 day','pending');
select set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='buyer'),true);
insert into public.tipster_follows(user_id,tipster_id) select (select id from v1_ids where k='buyer'),id from public.tipsters where user_id=(select id from v1_ids where k='expert');
update public.predictions set status='published',published_at=now() where id=(select id from v1_ids where k='prediction');
do $$ declare p uuid; begin
 if not exists(select 1 from public.notifications where user_id=(select id from v1_ids where k='buyer') and kind='new_prediction') then raise exception 'FAIL follow notification'; end if;
 if exists(select 1 from public.get_prediction_protected_content((select id from v1_ids where k='prediction'))) then raise exception 'FAIL paid content leak'; end if;
 p:=public.create_purchase((select id from v1_ids where k='prediction'));
 if p<>public.create_purchase((select id from v1_ids where k='prediction')) then raise exception 'FAIL purchase idempotency'; end if;
 if not exists(select 1 from public.purchases where id=p and platform_commission_tzs=600 and tipster_commission_tzs=1400) then raise exception 'FAIL 30/70 split'; end if;
 perform public.submit_manual_payment(p,'V1-'||p::text,null);
 perform set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='admin'),true);
 perform public.admin_verify_manual_payment(p,50);
 perform set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='buyer'),true);
 if not exists(select 1 from public.get_prediction_protected_content((select id from v1_ids where k='prediction')) where prediction_text like '%SECRET TEAMS%' and betslip_code='SECRET CODE') then raise exception 'FAIL unlock'; end if;
 perform set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='stranger'),true);
 if exists(select 1 from public.get_prediction_protected_content((select id from v1_ids where k='prediction'))) then raise exception 'FAIL cross-user unlock'; end if;
 begin update public.predictions set title='tampered' where id=(select id from v1_ids where k='prediction');raise exception 'FAIL mutation accepted';exception when others then if sqlerrm='FAIL mutation accepted' then raise;end if;end;
 begin delete from public.predictions where id=(select id from v1_ids where k='prediction');raise exception 'FAIL delete accepted';exception when others then if sqlerrm='FAIL delete accepted' then raise;end if;end;
 begin update public.predictions set result='won' where id=(select id from v1_ids where k='prediction');raise exception 'FAIL result forgery';exception when others then if sqlerrm='FAIL result forgery' then raise;end if;end;
 if has_column_privilege('anon','public.predictions','match_name','select') or has_column_privilege('authenticated','public.predictions','prediction_text','select') then raise exception 'FAIL protected column grants';end if;
 if has_function_privilege('authenticated','public.ingest_selection_result(uuid,public.prediction_result,text)','execute') then raise exception 'FAIL provider RPC public';end if;
end $$;
-- Verify actual RLS for another buyer.
grant select on v1_ids to authenticated;
set local role authenticated;
do $$ begin
 if exists(select 1 from public.notifications) then raise exception 'FAIL notification RLS';end if;
 if exists(select 1 from public.tipster_follows) then raise exception 'FAIL follow RLS';end if;
 if exists(select 1 from public.purchases) then raise exception 'FAIL purchases RLS';end if;
 begin insert into public.tipster_follows(user_id,tipster_id) select (select id from v1_ids where k='buyer'),id from public.tipsters where user_id=(select id from v1_ids where k='expert');raise exception 'FAIL follow ownership';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='buyer'),true);
insert into public.disputes(purchase_id,user_id,reason,details) select id,user_id,'content','Delivered content did not match preview.' from public.purchases where user_id=(select id from v1_ids where k='buyer');
select set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='admin'),true);
select public.admin_resolve_dispute((select id from public.disputes where user_id=(select id from v1_ids where k='buyer')),'approved','Content review confirmed a delivery issue.');
select public.admin_resolve_dispute((select id from public.disputes where user_id=(select id from v1_ids where k='buyer')),'refunded','Transfer completed and reconciled with Selcom.','V1-REFUND-TEST');
do $$ begin
 if exists(select 1 from public.wallets where user_id=(select id from v1_ids where k='expert') and pending_balance_tzs<>0) then raise exception 'FAIL refund balance reversal';end if;
 perform set_config('request.jwt.claim.sub',(select id::text from v1_ids where k='buyer'),true);
 if exists(select 1 from public.get_prediction_protected_content((select id from v1_ids where k='prediction'))) then raise exception 'FAIL refunded access';end if;
end $$;
select 'PASS: paid content, split, purchase idempotency, immutable history, notification/follow RLS, refund reversal' as verification;
rollback;
