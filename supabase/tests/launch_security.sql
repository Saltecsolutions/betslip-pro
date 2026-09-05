begin;
-- All fixtures are rolled back; no email or external payment is sent.
select set_config('test.buyer',gen_random_uuid()::text,true),set_config('test.tipster',gen_random_uuid()::text,true),set_config('test.admin',gen_random_uuid()::text,true);
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
values(current_setting('test.buyer')::uuid,'buyer-'||current_setting('test.buyer')||'@example.invalid',now(),'{"requested_role":"super_admin","age_confirmed":true}'),
(current_setting('test.tipster')::uuid,'tipster-'||current_setting('test.tipster')||'@example.invalid',now(),'{"requested_role":"tipster","age_confirmed":true}'),
(current_setting('test.admin')::uuid,'admin-'||current_setting('test.admin')||'@example.invalid',now(),'{"age_confirmed":true}');
do $$ begin
 if (select role from public.profiles where id=current_setting('test.buyer')::uuid)<>'bettor' then raise exception 'Signup privilege escalation'; end if;
 if has_column_privilege('authenticated','public.profiles','role','UPDATE') then raise exception 'Role writable';end if;
 if has_column_privilege('authenticated','public.tipsters','verification_status','UPDATE') then raise exception 'Self approval';end if;
 if has_column_privilege('anon','public.predictions','betslip_code','SELECT') then raise exception 'Paid content exposed';end if;
 if has_table_privilege('authenticated','public.purchases','INSERT') then raise exception 'Client price editable';end if;
end $$;
update public.profiles set role='super_admin' where id=current_setting('test.admin')::uuid;
update public.tipsters set verification_status='active' where user_id=current_setting('test.tipster')::uuid;
insert into public.policy_acceptances(user_id,document,version,locale) select current_setting(k)::uuid,d,case when d='seller' then '2026-09-05-v2' else '2026-09-05' end,'en' from unnest(array['test.buyer','test.tipster','test.admin']) k cross join unnest(array['terms','privacy','adult','seller']) d;
insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,betslip_code,price_tzs,match_date,status,odds)
select id,'Test','Football','Test match','Protected analysis','SECRET-TEST',1001,now()+interval '1 day','pending',2 from public.tipsters where user_id=current_setting('test.tipster')::uuid;
select set_config('test.prediction',(select id::text from public.predictions where title='Test' and tipster_id=(select id from public.tipsters where user_id=current_setting('test.tipster')::uuid)),true);
update public.predictions set status='published' where id=current_setting('test.prediction')::uuid and status='pending';
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.buyer'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if public.is_admin() then raise exception 'Buyer admin'; end if;
 if exists(select 1 from public.get_prediction_protected_content(current_setting('test.prediction')::uuid)) then raise exception 'Unlocked before payment';end if;
end $$;
select set_config('test.purchase',public.create_purchase(current_setting('test.prediction')::uuid)::text,true);
select public.submit_manual_payment(current_setting('test.purchase')::uuid,'TEST-'||current_setting('test.purchase'),null);
do $$ begin
 begin
  perform public.admin_verify_manual_payment(current_setting('test.purchase')::uuid,0);
  raise exception 'Buyer verified payment';
 exception when raise_exception then
  if sqlerrm<>'Finance permission required' then raise; end if;
 end;
 if exists(select 1 from public.get_prediction_protected_content(current_setting('test.prediction')::uuid)) then raise exception 'Submission unlocked content'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.admin'),'role','authenticated')::text,true);
set local role authenticated;
select public.admin_verify_manual_payment(current_setting('test.purchase')::uuid,25);
reset role;
do $$ begin
 if not exists(select 1 from public.purchases where id=current_setting('test.purchase')::uuid and platform_commission_tzs=600 and tipster_commission_tzs=400 and processing_fee_tzs=25 and payment_status='paid') then raise exception 'Split failure';end if;
 if (select pending_balance_tzs from public.wallets where user_id=current_setting('test.tipster')::uuid)<>400 then raise exception 'Wallet credit failure';end if;
 if (select count(*) from public.ledger_entries where purchase_id=current_setting('test.purchase')::uuid)<>5 then raise exception 'Ledger failure';end if;
end $$;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.buyer'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if public.get_betslip_code(current_setting('test.prediction')::uuid)<>'SECRET-TEST' then raise exception 'Paid unlock failure';end if;
end $$;
reset role;
rollback;
select 'PASS: roles, protected content, authoritative price, admin payment, 30/70 split, ledger, wallet and unlock; fixtures rolled back' as result;
