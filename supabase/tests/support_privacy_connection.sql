begin;
create temporary table privacy_test(k text primary key,id uuid);
insert into privacy_test values('buyer',gen_random_uuid()),('admin',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id::text||'@test.invalid',now(),'{}' from privacy_test;
update public.profiles set role='super_admin' where id=(select id from privacy_test where k='admin');
with q as (insert into support.tickets(user_id,subject,category) select id,'Privacy integration test','technical' from privacy_test where k='buyer' returning id) insert into privacy_test select 'ticket',id from q;
insert into support.messages(ticket_id,kind,body,internal) select id,'customer','Visible customer message',false from privacy_test where k='ticket';
insert into support.messages(ticket_id,kind,body,internal) select id,'staff','CONFIDENTIAL STAFF NOTE',true from privacy_test where k='ticket';
with q as (insert into public.privacy_requests(user_id,kind,details) select id,'deletion','Rollback test deletion request' from privacy_test where k='buyer' returning id) insert into privacy_test select 'request',id from q;
grant all on privacy_test to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from privacy_test where k='buyer'),true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.export_my_data();
 if jsonb_array_length(r->'support_tickets') is distinct from 1 then raise exception 'FAIL support tickets missing in export';end if;
 if jsonb_array_length(r->'support_messages') is distinct from 1 or r::text like '%CONFIDENTIAL STAFF NOTE%' or r::text not like '%Visible customer message%' then raise exception 'FAIL customer message export';end if;
end $$;
select set_config('request.jwt.claim.sub',(select id::text from privacy_test where k='admin'),true);
select public.admin_restrict_account((select id from privacy_test where k='request'),'Rollback privacy workflow test with retained audit records');
reset role;
do $$begin
 if not exists(select 1 from support.tickets where id=(select id from privacy_test where k='ticket') and redacted_at is not null) then raise exception 'FAIL account workflow did not redact ticket';end if;
 if exists(select 1 from support.messages where ticket_id=(select id from privacy_test where k='ticket') and body='Visible customer message') then raise exception 'FAIL customer body retained';end if;
end $$;
select 'PASS: actual public export includes customer tickets only; actual account restriction redacts support history' as result;
rollback;
