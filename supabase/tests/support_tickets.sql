begin;
create temporary table support_test(k text primary key,id uuid,payload jsonb);
insert into support_test(k,id) values('owner',gen_random_uuid()),('other',gen_random_uuid()),('agent',gen_random_uuid()),('super',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id::text||'@test.invalid',now(),'{}' from support_test;
update public.profiles set status='active',role=case when id=(select id from support_test where k='super') then 'super_admin'::public.app_role else role end where id in(select id from support_test);
insert into support.agents(user_id) select id from support_test where k='agent';
grant all on support_test to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from support_test where k='owner'),true);
set local role authenticated;
do $$declare r jsonb;k uuid:=gen_random_uuid();begin
 r:=public.support_api('create',jsonb_build_object('key',k,'subject','Cannot open my page','body','The page fails to load on my phone.','category','technical','email_updates',true));
 insert into support_test(k,id,payload) values('ticket',(r->>'id')::uuid,r);
 if public.support_api('create',jsonb_build_object('key',k))->>'id'<>r->>'id' then raise exception 'FAIL create idempotency';end if;
 if public.support_api('get',jsonb_build_object('id',r->>'id'))->'ticket'->>'status'<>'open' then raise exception 'FAIL initial status';end if;
 begin perform public.support_api('list','{"team":true}');raise exception 'FAIL customer team access';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
 if has_table_privilege('authenticated','support.tickets','select') or has_function_privilege('authenticated','support.escalate()','execute') then raise exception 'FAIL exposed internals';end if;
 begin perform public.support_api('create',jsonb_build_object('key',gen_random_uuid(),'subject','Wrong purchase','body','A purchase that does not belong to me','category','payment','purchase_id',gen_random_uuid()));raise exception 'FAIL purchase ownership';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from support_test where k='other'),true);
do $$begin
 begin perform public.support_api('get',jsonb_build_object('id',(select id from support_test where k='ticket')));raise exception 'FAIL cross-user read';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.support_api('reply',jsonb_build_object('id',(select id from support_test where k='ticket'),'key',gen_random_uuid(),'body','Unauthorized reply'));raise exception 'FAIL cross-user reply';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from support_test where k='agent'),true);
do $$declare tid uuid:=(select id from support_test where k='ticket');begin
 perform public.support_api('reply',jsonb_build_object('team',true,'id',tid,'key',gen_random_uuid(),'body','PRIVATE STAFF NOTE','internal',true));
 perform public.support_api('reply',jsonb_build_object('team',true,'id',tid,'key',gen_random_uuid(),'body','Please tell us which browser you use.','status','waiting_customer'));
 if public.support_api('get',jsonb_build_object('team',true,'id',tid))->'ticket'->>'status'<>'waiting_customer' then raise exception 'FAIL staff reply';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from support_test where k='owner'),true);
do $$declare tid uuid:=(select id from support_test where k='ticket');r jsonb;k uuid:=gen_random_uuid();begin
 r:=public.support_api('get',jsonb_build_object('id',tid));
 if r::text like '%PRIVATE STAFF NOTE%' then raise exception 'FAIL private note leaked';end if;
 if public.export_my_data()::text like '%PRIVATE STAFF NOTE%' then raise exception 'FAIL export note leaked';end if;
 perform public.support_api('reply',jsonb_build_object('id',tid,'key',k,'body','I am using Safari on iPhone.'));
 perform public.support_api('reply',jsonb_build_object('id',tid,'key',k,'body','I am using Safari on iPhone.'));
 if public.support_api('get',jsonb_build_object('id',tid))->'ticket'->>'status'<>'open' then raise exception 'FAIL customer reopens';end if;
end $$;
reset role;
do $$declare tid uuid:=(select id from support_test where k='ticket');n bigint;begin
 if (select count(*) from support.messages where ticket_id=tid and body='I am using Safari on iPhone.')<>1 then raise exception 'FAIL reply dedup';end if;
 if (select count(*) from admin_alerts.outbox where kind='support_customer' and summary->>'ticket_id'=tid::text)<>2 then raise exception 'FAIL customer email events/internal note email';end if;
 if exists(select 1 from admin_alerts.outbox where kind='support_customer' and summary::text like '%PRIVATE STAFF NOTE%') then raise exception 'FAIL private email';end if;
 update support.tickets set due_at=now()-interval '1 hour' where id=tid;
 perform support.escalate();select count(*) into n from admin_alerts.outbox where event_key like 'support-overdue/'||tid||'/%';
 perform support.escalate();if n<>1 or (select count(*) from admin_alerts.outbox where event_key like 'support-overdue/'||tid||'/%')<>1 then raise exception 'FAIL escalation dedup';end if;
 update support.tickets set category='payment' where id=tid;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from support_test where k='agent'),true);
set local role authenticated;
do $$begin
 begin perform public.support_api('get',jsonb_build_object('team',true,'id',(select id from support_test where k='ticket')));raise exception 'FAIL nonfinance access';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
reset role;
do $$declare summary jsonb;begin
 select o.summary into summary from admin_alerts.outbox o where kind='support_customer' and o.summary->>'ticket_id'=(select id::text from support_test where k='ticket') limit 1;
 if not support.email_allowed(summary) then raise exception 'FAIL valid recipient';end if;
 update support.tickets set email_updates=false where id=(select id from support_test where k='ticket');
 if support.email_allowed(summary) then raise exception 'FAIL email optout';end if;
 if has_function_privilege('anon','public.support_api(text,jsonb)','execute') then raise exception 'FAIL anon access';end if;
end $$;
select 'PASS: ownership, scoped support, finance isolation, private notes, export, idempotency, email optout and overdue deduplication' as result;
rollback;
