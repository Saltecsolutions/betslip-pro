begin;
create temporary table alert_test_ids(k text,id uuid);
insert into alert_test_ids values('owner',gen_random_uuid()),('admin',gen_random_uuid()),('super',gen_random_uuid());
insert into auth.users(id,email,raw_user_meta_data) select id,id::text||'@test.invalid','{}'::jsonb from alert_test_ids;
update public.profiles set status='active',role=case when id=(select id from alert_test_ids where k='super') then 'super_admin'::public.app_role when id=(select id from alert_test_ids where k='admin') then 'admin'::public.app_role else role end where id in(select id from alert_test_ids);
grant select on alert_test_ids to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from alert_test_ids where k='owner'),true);
set local role authenticated;
do $$begin
 begin perform public.admin_alerts_manage('read');raise exception 'FAIL owner allowed';exception when others then if sqlerrm='FAIL owner allowed' then raise;end if;end;
 if has_function_privilege('authenticated','public.admin_alerts_claim(text,boolean)','execute') or has_table_privilege('authenticated','admin_alerts.outbox','select') then raise exception 'FAIL private worker exposure';end if;
end$$;
select set_config('request.jwt.claim.sub',(select id::text from alert_test_ids where k='admin'),true);
do $$begin
 begin perform public.admin_alerts_manage('test');raise exception 'FAIL regular admin allowed';exception when others then if sqlerrm='FAIL regular admin allowed' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',(select id::text from alert_test_ids where k='super'),true);
select public.admin_alerts_manage('test')->'settings'->>'recipient' as recipient;
do $$begin
 if public.admin_alerts_manage('read')->'settings'->>'recipient'<>'salmin@saltecsolutions.co.tz' then raise exception 'FAIL recipient';end if;
 begin perform public.admin_alerts_manage('test');raise exception 'FAIL test throttle';exception when others then if sqlerrm='FAIL test throttle' then raise;end if;end;
end$$;
reset role;
do $$declare token text; batch jsonb; row1 jsonb;begin
 select decrypted_secret into token from vault.decrypted_secrets where name='betslip_admin_alerts_worker';
 begin perform admin_alerts.claim(repeat('0',64),true);raise exception 'FAIL invalid token';exception when others then if sqlerrm='FAIL invalid token' then raise;end if;end;
 if admin_alerts.claim(token,false)<>'[]'::jsonb then raise exception 'FAIL missing key claims';end if;
 batch:=admin_alerts.claim(token,true);if jsonb_array_length(batch)<1 then raise exception 'FAIL claim';end if;
 row1:=batch->0;
 if admin_alerts.finish((row1->>'id')::uuid,gen_random_uuid(),'bad',null,false) then raise exception 'FAIL stale lease';end if;
 if not admin_alerts.finish((row1->>'id')::uuid,(row1->>'lease_token')::uuid,null,'resend_http_429',true) then raise exception 'FAIL retry';end if;
 if not exists(select 1 from admin_alerts.outbox where id=(row1->>'id')::uuid and status='pending' and next_attempt_at>now()) then raise exception 'FAIL backoff';end if;
 update admin_alerts.outbox set first_attempt_at=now()-interval '21 hours' where id=(row1->>'id')::uuid;
 perform admin_alerts.claim(token,true);
 if not exists(select 1 from admin_alerts.outbox where id=(row1->>'id')::uuid and status='failed') then raise exception 'FAIL expiry';end if;
 if has_function_privilege('anon','public.admin_alerts_manage(text,boolean)','execute') or has_function_privilege('anon','public.admin_alerts_claim(text,boolean)','execute') then raise exception 'FAIL anon';end if;
end$$;
select 'PASS: superadmin authorization, token validation, lease protection, backoff, expiry and no public access' as result;
rollback;
