begin;
create temp table ids(k text primary key,id uuid);
insert into ids values('seller',gen_random_uuid()),('buyer',gen_random_uuid()),('admin',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id||'@test.invalid',now(),'{}' from ids;
insert into public.policy_acceptances(user_id,document,version,locale) select id,d,case when d='seller' then '2026-09-05-v2' else '2026-09-05' end,'en' from ids cross join unnest(array['terms','privacy','adult','seller']) d;
update public.profiles set role='super_admin' where id=(select id from ids where k='admin');
insert into public.tipsters(user_id,display_name,verification_status) select id,'Pricing test','active' from ids where k='seller';
insert into ids select 'tid',id from public.tipsters where user_id=(select id from ids where k='seller');
grant all on ids to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from ids where k='seller'),true);
set local role authenticated;
do $$declare d jsonb;r jsonb;begin
 d:=jsonb_build_object('title','Approved first slip','sport','Football','match_name','A vs B','prediction_text','Home team wins','analysis','A complete preview for this submission test.','match_date',now()+interval '1 day','odds',2,'selection_count',1,'bookmaker','BetPawa','betslip_code','DIRECT-001','price_tzs',9999);
 begin perform public.submit_prediction(d||jsonb_build_object('match_date',now()-interval '1 hour'));raise exception 'FAIL past kickoff';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 r:=public.submit_prediction(d);
 if r->>'status'<>'published' or jsonb_array_length(r->'reasons')<>0 then raise exception 'FAIL first slip requires approval: %',r;end if;
 if not exists(select 1 from public.predictions where id=(r->>'id')::uuid and status='published' and published_at is not null and price_tzs=1000) then raise exception 'FAIL publication or price snapshot';end if;
end $$;
reset role;
insert into public.tipsters(user_id,display_name,verification_status) select id,'Not approved','pending' from ids where k='buyer';
select set_config('request.jwt.claim.sub',(select id::text from ids where k='buyer'),true);
set local role authenticated;
do $$begin
 begin perform public.submit_prediction('{}');raise exception 'FAIL unapproved can submit';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
reset role;
update public.tipsters set verification_status='active' where user_id=(select id from ids where k='buyer');
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.submit_prediction(jsonb_build_object('title','Flagged large odds','sport','Football','match_name','A vs B','prediction_text','Home team wins','analysis','A complete preview for this submission test.','match_date',now()+interval '1 day','odds',150,'selection_count',1,'bookmaker','BetPawa','betslip_code','FLAG-001'));
 if r->>'status'<>'pending' or not(r->'reasons'?'odds_or_size') or r->'reasons'?'probation' or r->'reasons'?'identity_review' then raise exception 'FAIL risk review behavior: %',r;end if;
end $$;
reset role;
rollback;
