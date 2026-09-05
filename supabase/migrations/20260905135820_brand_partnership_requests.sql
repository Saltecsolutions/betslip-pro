begin;
create schema if not exists partnerships;
revoke all on schema partnerships from public,anon;
grant usage on schema partnerships to authenticated;
create table partnerships.requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 business text not null check(length(business) between 2 and 120),
 sector text not null check(sector in ('bookmaker','consumer','telecom','sports','hospitality','other')),
 objective text not null check(length(objective) between 10 and 2000),
 budget_tzs bigint not null check(budget_tzs between 1 and 100000000000),
 start_date date not null, end_date date not null check(end_date>=start_date),
 placement text not null check(placement in ('homepage','matchday','category','custom')),
 status text not null default 'submitted' check(status in ('submitted','reviewing','proposal','closed')),
 response text not null default '' check(length(response)<=4000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table partnerships.requests enable row level security;
revoke all on partnerships.requests from public,anon,authenticated;
create index on partnerships.requests(user_id,created_at desc);
create function partnerships.submit_request(p_business text,p_sector text,p_objective text,p_budget_tzs bigint,p_start_date date,p_end_date date,p_placement text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') or not coalesce(compliance.accepted(auth.uid()),false) then raise exception 'Active account and current policy acceptance required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,981));
 if (select count(*) from partnerships.requests where user_id=auth.uid() and created_at>now()-interval '1 day')>=5 then raise exception 'Daily request limit reached'; end if;
 if p_start_date<current_date then raise exception 'Choose a future campaign date'; end if;
 insert into partnerships.requests(user_id,business,sector,objective,budget_tzs,start_date,end_date,placement) values(auth.uid(),btrim(p_business),p_sector,btrim(p_objective),p_budget_tzs,p_start_date,p_end_date,p_placement) returning id into v_id;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id) values(auth.uid(),'partnership_requested','partnership',v_id::text);
 return v_id;
end $$;
create function partnerships.read_requests(p_admin boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'Active account required'; end if;
 if p_admin and not public.is_admin() then raise exception 'Admin only'; end if;
 if p_admin then insert into public.audit_logs(actor_user_id,action,entity_type) values(auth.uid(),'partnership_queue_read','partnership'); end if;
 return coalesce((select jsonb_agg(to_jsonb(r)-'user_id' order by r.created_at desc) from partnerships.requests r where (p_admin or r.user_id=auth.uid())),'[]'::jsonb);
end $$;
create function partnerships.review_request(p_id uuid,p_status text,p_response text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Admin only'; end if;
 if p_status not in ('reviewing','proposal','closed') or p_status is null or length(btrim(coalesce(p_response,''))) not between 5 and 4000 then raise exception 'Status and response required'; end if;
 update partnerships.requests set status=p_status,response=btrim(p_response),updated_at=now() where id=p_id;
 if not found then raise exception 'Request not found'; end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'partnership_reviewed','partnership',p_id::text,jsonb_build_object('status',p_status));
end $$;
create function public.submit_partnership_request(p_business text,p_sector text,p_objective text,p_budget_tzs bigint,p_start_date date,p_end_date date,p_placement text) returns uuid language sql security invoker set search_path='' as $$ select partnerships.submit_request(p_business,p_sector,p_objective,p_budget_tzs,p_start_date,p_end_date,p_placement); $$;
create function public.read_partnership_requests(p_admin boolean default false) returns jsonb language sql security invoker set search_path='' as $$ select partnerships.read_requests(p_admin); $$;
create function public.review_partnership_request(p_id uuid,p_status text,p_response text) returns void language sql security invoker set search_path='' as $$ select partnerships.review_request(p_id,p_status,p_response); $$;
revoke all on all functions in schema partnerships from public,anon;
grant execute on all functions in schema partnerships to authenticated;
revoke all on function public.submit_partnership_request(text,text,text,bigint,date,date,text),public.read_partnership_requests(boolean),public.review_partnership_request(uuid,text,text) from public,anon;
grant execute on function public.submit_partnership_request(text,text,text,bigint,date,date,text),public.read_partnership_requests(boolean),public.review_partnership_request(uuid,text,text) to authenticated;
commit;
