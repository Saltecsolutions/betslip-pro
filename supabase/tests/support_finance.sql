begin;
create temporary table support_finance_test(k text primary key,id uuid);
insert into support_finance_test values('buyer',gen_random_uuid()),('seller',gen_random_uuid()),('super',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id::text||'@test.invalid',now(),'{}' from support_finance_test;
update public.profiles set status='active',role=case when id=(select id from support_finance_test where k='super') then 'super_admin'::public.app_role else role end where id in(select id from support_finance_test);
insert into public.policy_acceptances(user_id,document,version,locale) select id,d,'2026-09-05','en' from support_finance_test cross join unnest(array['terms','privacy','adult','seller']) d;
insert into public.tipsters(user_id,display_name) select id,'Support test seller' from support_finance_test where k='seller';
with p as (insert into public.predictions(tipster_id,title,sport,match_name,prediction_text,match_date) select id,'Support test fixture','football','Test A vs B','Testing only',now()+interval '2 days' from public.tipsters where user_id=(select id from support_finance_test where k='seller') returning id) insert into support_finance_test select 'prediction',id from p;
with p as (insert into public.purchases(user_id,prediction_id,tipster_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_status) select (select id from support_finance_test where k='buyer'),(select id from support_finance_test where k='prediction'),id,1000,300,700,'submitted' from public.tipsters where user_id=(select id from support_finance_test where k='seller') returning id) insert into support_finance_test select 'purchase',id from p;
grant all on support_finance_test to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from support_finance_test where k='buyer'),true);
set local role authenticated;
do $$declare r jsonb;other jsonb;begin
 r:=public.support_api('create',jsonb_build_object('key',gen_random_uuid(),'subject','Refund for missing purchased slip','body','The purchased slip is unavailable on my account.','category','refund','purchase_id',(select id from support_finance_test where k='purchase')));
 insert into support_finance_test values('ticket',(r->>'id')::uuid);
 if public.support_api('get',jsonb_build_object('id',r->>'id'))->'dispute'->>'status'<>'open' then raise exception 'FAIL linked dispute';end if;
 other:=public.support_api('create',jsonb_build_object('key',gen_random_uuid(),'subject','Duplicate purchase complaint','body','Same purchased slip is still unavailable.','category','refund','purchase_id',(select id from support_finance_test where k='purchase')));
 if other->>'id'<>r->>'id' then raise exception 'FAIL duplicate purchase review';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from support_finance_test where k='super'),true);
do $$begin
 begin perform public.support_api('reply',jsonb_build_object('team',true,'id',(select id from support_finance_test where k='ticket'),'key',gen_random_uuid(),'body','Closing without a finance decision','status','resolved'));raise exception 'FAIL unresolved refund closure';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
reset role;
update public.disputes set status='rejected',resolution='Test decision only; no refund transfer executed.' where purchase_id=(select id from support_finance_test where k='purchase');
do $$declare tid uuid:=(select id from support_finance_test where k='ticket');uid uuid:=(select id from support_finance_test where k='buyer');general uuid;begin
 if (select status from support.tickets where id=tid)<>'resolved' then raise exception 'FAIL dispute status sync';end if;
 if not exists(select 1 from support.messages where ticket_id=tid and body like '%Test decision only%') then raise exception 'FAIL decision message';end if;
 insert into support.tickets(user_id,subject,category) values(uid,'Private ordinary request','technical') returning id into general;
 insert into support.messages(ticket_id,author_id,kind,body) values(general,uid,'customer','PERSONAL DETAILS TO REMOVE');
 perform support.restrict_account(uid);
 if exists(select 1 from support.messages where ticket_id=general and body='PERSONAL DETAILS TO REMOVE') then raise exception 'FAIL privacy redaction';end if;
 if not exists(select 1 from support.messages where ticket_id=tid and body like '%Test decision only%') then raise exception 'FAIL financial record preservation';end if;
 if (select redacted_at from support.tickets where id=general) is null then raise exception 'FAIL archive';end if;
end $$;
select 'PASS: purchase ownership, refund link/dedup, finance decision synchronization, closure guard and privacy preservation' as result;
rollback;
