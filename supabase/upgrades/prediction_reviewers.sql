begin;
create schema moderation;
revoke all on schema moderation from public,anon;
grant usage on schema moderation to authenticated;
create table moderation.reviewers(email text primary key check(email=lower(btrim(email))),enabled boolean not null default true,granted_by uuid references public.profiles(id),reason text not null,updated_at timestamptz not null default now());
alter table moderation.reviewers enable row level security;
revoke all on moderation.reviewers from public,anon,authenticated,service_role;
create function moderation.can_review() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid() and p.status='active' and u.email_confirmed_at is not null
 and (p.role='super_admin' or exists(select 1 from moderation.reviewers r where r.email=lower(u.email) and r.enabled)));
$$;
create function public.prediction_review_access() returns boolean language sql security invoker set search_path='' as $$select moderation.can_review();$$;
create function moderation.snapshot(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('prediction',to_jsonb(p),'selections',coalesce((select jsonb_agg(s order by s.id) from public.prediction_selections s where s.prediction_id=p.id),'[]')) from public.predictions p where p.id=p_id;
$$;
create function moderation.api(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.predictions; snap jsonb;result jsonb;decision text;owner_id uuid;offset_n integer;actor uuid:=auth.uid();
begin
 if p_action='grant' then
 if not admin_alerts.is_superadmin() then raise exception 'Superadmin required';end if;
 if length(btrim(coalesce(p_data->>'reason','')))<10 or coalesce(p_data->>'email','')!~'^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'Email and reason required';end if;
 insert into moderation.reviewers(email,enabled,granted_by,reason) values(lower(btrim(p_data->>'email')),coalesce((p_data->>'enabled')::boolean,false),actor,left(p_data->>'reason',500)) on conflict(email) do update set enabled=excluded.enabled,granted_by=actor,reason=excluded.reason,updated_at=now();
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(actor,'staff_permissions','prediction_reviewer',jsonb_build_object('email',lower(btrim(p_data->>'email')),'enabled',p_data->'enabled','reason',left(p_data->>'reason',500)));
 return jsonb_build_object('ok',true);
 end if;
 if not moderation.can_review() then raise exception 'Prediction review permission required / Ruhusa ya kukagua mikeka inahitajika';end if;
 if not compliance.accepted(actor) then raise exception 'Accept current account policies / Kubali sera kwenye akaunti';end if;
 if p_action='list' then
 offset_n:=greatest(0,least(10000,coalesce((p_data->>'offset')::integer,0)));
 select coalesce(jsonb_agg(x),'[]') into result from (select q.id,q.title,q.category,q.match_date,q.odds,q.status,t.display_name from public.predictions q join public.tipsters t on t.id=q.tipster_id where q.status='pending' and q.published_at is null and t.user_id<>actor order by q.created_at,q.id limit 50 offset offset_n) x;
 insert into public.audit_logs(actor_user_id,action,entity_type) values(actor,'prediction_review_queue','prediction');return result;
 end if;
 select * into p from public.predictions where id=(p_data->>'id')::uuid for update;
 if not found or p.status<>'pending' or p.published_at is not null then raise exception 'Pending submission required / Mkeka unaosubiri ukaguzi unahitajika';end if;
 select user_id into owner_id from public.tipsters where id=p.tipster_id;
 if owner_id=actor then raise exception 'You cannot approve your own submission / Huwezi kuapprove mkeka wako mwenyewe';end if;
 if p_action='get' then
 snap:=moderation.snapshot(p.id);
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id) values(actor,'prediction_review_read','prediction',p.id::text);
 return snap||jsonb_build_object('revision',md5(snap::text));
 elsif p_action='decide' then
 decision:=p_data->>'decision';
 if decision is null or decision not in ('published','rejected') or length(btrim(coalesce(p_data->>'reason','')))<10 then raise exception 'Decision and review note required / Uamuzi na maelezo ya ukaguzi yanahitajika';end if;
 lock table public.prediction_selections in share mode;
 snap:=moderation.snapshot(p.id);
 if p_data->>'revision' is distinct from md5(snap::text) then raise exception 'Submission changed. Reload and review again / Mkeka umebadilika. Kagua tena';end if;
 if p.match_date<=now() then raise exception 'First event has already started / Mechi ya kwanza imeanza';end if;
 if decision='published' and (not compliance.accepted(owner_id,true) or not exists(select 1 from public.tipsters where id=p.tipster_id and verification_status='active')) then raise exception 'Active tipster and seller acceptance required';end if;
 if decision='published' and (p.odds is null or p.odds<=1 or length(btrim(p.prediction_text))=0 or length(btrim(p.match_name))=0) then raise exception 'Complete selections and odds required';end if;
 update public.predictions set status=decision::public.prediction_status where id=p.id;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(actor,'prediction_review_decision','prediction',p.id::text,jsonb_build_object('decision',decision,'reason',left(p_data->>'reason',1000),'revision',p_data->>'revision'));
 insert into public.notifications(user_id,kind,title_en,title_sw,href) values(owner_id,'review',case when decision='published' then 'Your submission was published' else 'Your submission needs changes' end,case when decision='published' then 'Mkeka wako umechapishwa' else 'Mkeka wako unahitaji marekebisho' end,'/tipster');
 return jsonb_build_object('ok',true);
 end if;
 raise exception 'Invalid review action';
end $$;
create function public.prediction_review(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select moderation.api(p_action,p_data);$$;
revoke all on all functions in schema moderation from public,anon,authenticated,service_role;
grant execute on function moderation.can_review(),moderation.api(text,jsonb) to authenticated;
revoke all on function public.prediction_review_access(),public.prediction_review(text,jsonb) from public,anon,authenticated;
grant execute on function public.prediction_review_access(),public.prediction_review(text,jsonb) to authenticated;
commit;
