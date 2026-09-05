begin;
create schema support;
revoke all on schema support from public,anon;
grant usage on schema support to authenticated;
create table support.agents(user_id uuid primary key references public.profiles(id),enabled boolean not null default true);
create table support.tickets(
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 user_id uuid not null references public.profiles(id), subject text not null check(length(subject) between 5 and 140),
 category text not null check(category in ('account','technical','general','payment','content','refund')),
 status text not null default 'open' check(status in ('open','in_progress','waiting_customer','resolved','closed')),
 purchase_id uuid references public.purchases(id),dispute_id uuid unique references public.disputes(id),
 assigned_to uuid references public.profiles(id),email_updates boolean not null default false,
 request_key uuid,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 due_at timestamptz,escalated_at timestamptz,redacted_at timestamptz,
 unique(user_id,request_key)
);
create table support.messages(
 id uuid primary key default gen_random_uuid(),ticket_id uuid not null references support.tickets(id),
 author_id uuid references public.profiles(id),kind text not null check(kind in ('customer','staff','system')),
 internal boolean not null default false,body text not null check(length(body) between 1 and 4000),
 request_key uuid,created_at timestamptz not null default now(),unique(ticket_id,author_id,request_key)
);
create index support_owner on support.tickets(user_id,updated_at desc);
create index support_queue on support.tickets(status,due_at);
create index support_assignee on support.tickets(assigned_to) where status not in ('resolved','closed');
create index support_purchase on support.tickets(purchase_id);
create index support_messages_ticket on support.messages(ticket_id,created_at);
alter table support.agents enable row level security;
alter table support.tickets enable row level security;
alter table support.messages enable row level security;
revoke all on all tables in schema support from public,anon,authenticated,service_role;
revoke all on all sequences in schema support from public,anon,authenticated,service_role;

create function support.is_agent(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=p_user and p.status='active' and (p.role='super_admin' or exists(select 1 from support.agents a where a.user_id=p.id and a.enabled)));
$$;
create function support.is_finance(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=p_user and p.status='active' and (p.role='super_admin' or (p.role='admin' and exists(select 1 from compliance.staff_access a where a.user_id=p.id and a.finance))));
$$;
create function support.eligible(p_user uuid,p_category text) returns boolean language sql stable security definer set search_path='' as $$
 select support.is_agent(p_user) and (p_category not in ('payment','content','refund') or support.is_finance(p_user));
$$;
create function support.assign(p_category text) returns uuid language sql security definer set search_path='' as $$
 select p.id from public.profiles p where support.eligible(p.id,p_category)
 order by (p.role='super_admin'),(select count(*) from support.tickets t where t.assigned_to=p.id and t.status not in ('resolved','closed')),p.id limit 1;
$$;
create function support.due(p_category text) returns timestamptz language sql stable set search_path='' as $$
 select now()+case when p_category in ('payment','content','refund') then interval '4 hours' else interval '24 hours' end;
$$;
alter table admin_alerts.outbox drop constraint outbox_kind_check;
alter table admin_alerts.outbox add constraint outbox_kind_check check(kind in ('partnership','privacy','permissions','dispute','payment_failed','integrity','test','partner_weekly','support_customer','support_escalation'));
create function support.notify_customer(p_ticket uuid,p_event text) returns void language plpgsql security definer set search_path='' as $$
declare t support.tickets; addr text;
begin
 select * into strict t from support.tickets where id=p_ticket;
 insert into public.notifications(user_id,kind,title_en,title_sw,href) values(t.user_id,'support','Ticket BP-'||t.number||' updated','Ticket BP-'||t.number||' imesasishwa','/support/'||t.id);
 select email into addr from auth.users where id=t.user_id and email_confirmed_at is not null and email is not null;
 if t.email_updates and addr is not null then
 insert into admin_alerts.outbox(event_key,kind,summary) values('support/'||p_event,'support_customer',jsonb_build_object('ticket_id',t.id,'number',t.number,'email',addr)) on conflict(event_key) do nothing;
 end if;
end $$;
create function support.notify_agent(p_ticket uuid) returns void language plpgsql security definer set search_path='' as $$
declare t support.tickets;
begin
 select * into strict t from support.tickets where id=p_ticket;
 if t.assigned_to is not null then insert into public.notifications(user_id,kind,title_en,title_sw,href) values(t.assigned_to,'support','Support ticket BP-'||t.number||' needs attention','Ticket BP-'||t.number||' inahitaji hatua','/support/team/'||t.id);end if;
end $$;

-- The existing dispute remains the source of truth for refund decisions and transfers.
create function support.capture_dispute() returns trigger language plpgsql security definer set search_path='' as $$
declare tid uuid;mid uuid;
begin
 if TG_OP='INSERT' then
 insert into support.tickets(user_id,subject,category,purchase_id,dispute_id,assigned_to,due_at)
 values(new.user_id,'Purchase review / Ukaguzi wa ununuzi','refund',new.purchase_id,new.id,support.assign('refund'),support.due('refund')) returning id into tid;
 insert into support.messages(ticket_id,author_id,kind,body) values(tid,new.user_id,'customer',new.details);
 perform support.notify_agent(tid);
 elsif new.status is distinct from old.status or new.resolution is distinct from old.resolution then
 select id into tid from support.tickets where dispute_id=new.id;
 if tid is not null then
 update support.tickets set status=case when new.status in ('refunded','rejected') then 'resolved' else 'in_progress' end,
 updated_at=now(),due_at=case when new.status in ('refunded','rejected') then null else support.due('refund') end,escalated_at=null where id=tid;
 insert into support.messages(ticket_id,author_id,kind,body) values(tid,auth.uid(),'system',left('Purchase review / Ukaguzi wa ununuzi: '||new.status||'. '||coalesce(new.resolution,''),4000)) returning id into mid;
 perform support.notify_customer(tid,mid::text);
 end if;
 end if;
 return new;
end $$;
-- Preserve older reviews without generating historical email or notification floods.
insert into support.tickets(user_id,subject,category,purchase_id,dispute_id,assigned_to,status,created_at,updated_at,due_at)
 select user_id,'Purchase review / Ukaguzi wa ununuzi','refund',purchase_id,id,support.assign('refund'),case when status in ('refunded','rejected') then 'resolved' else 'open' end,created_at,updated_at,case when status in ('open','approved') then support.due('refund') end from public.disputes;
insert into support.messages(ticket_id,author_id,kind,body,created_at) select t.id,d.user_id,'customer',d.details,d.created_at from public.disputes d join support.tickets t on t.dispute_id=d.id;
insert into support.messages(ticket_id,kind,body,created_at) select t.id,'system',left('Purchase review / Ukaguzi wa ununuzi: '||d.status||'. '||d.resolution,4000),d.updated_at from public.disputes d join support.tickets t on t.dispute_id=d.id where d.resolution is not null;
create trigger support_dispute after insert or update on public.disputes for each row execute function support.capture_dispute();

create function support.api(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare uid uuid:=auth.uid();t support.tickets;tid uuid;mid uuid;rid uuid;key uuid;team boolean:=coalesce((p_payload->>'team')::boolean,false);st text;cat text;body text;v_subject text;pid uuid;agent uuid;result jsonb;internal_note boolean;page integer;
begin
 if uid is null or not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where u.id=uid and p.status='active' and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)) then raise exception 'Verified active account required / Akaunti iliyothibitishwa inahitajika';end if;
 if team and not support.is_agent(uid) then raise exception 'Support permission required / Ruhusa ya support inahitajika';end if;
 if p_action='bootstrap' then
 return jsonb_build_object('staff',support.is_agent(uid),'superadmin',admin_alerts.is_superadmin(),'finance',support.is_finance(uid),
 'purchases',coalesce((select jsonb_agg(x) from (select id,payment_status,amount_tzs from public.purchases where user_id=uid order by created_at desc limit 200) x),'[]'),
 'agents',case when support.is_agent(uid) then coalesce((select jsonb_agg(x) from (select p.id,p.full_name,support.is_finance(p.id) finance from public.profiles p where support.is_agent(p.id)) x),'[]') else '[]'::jsonb end);
 elsif p_action='list' then
 page:=greatest(0,least(10000,coalesce((p_payload->>'offset')::integer,0)));
 select coalesce(jsonb_agg(x order by x.updated_at desc),'[]') into result from (
 select id,number,subject,category,status,assigned_to,created_at,updated_at,due_at,escalated_at from support.tickets t
 where (case when team then support.eligible(uid,t.category) else t.user_id=uid end)
 and (coalesce(p_payload->>'status','all')='all' or t.status=p_payload->>'status' or (p_payload->>'status'='active' and t.status not in ('resolved','closed')) or (p_payload->>'status'='overdue' and t.due_at<now() and t.status in ('open','in_progress')))
 and (coalesce(p_payload->>'search','')='' or t.number::text=replace(upper(p_payload->>'search'),'BP-','') or t.subject ilike '%'||left(p_payload->>'search',100)||'%')
 order by updated_at desc,id limit 50 offset page) x;
 if team then insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(uid,'support_queue_read','support',jsonb_build_object('offset',page));end if;
 return result;
 elsif p_action='create' then
 key:=(p_payload->>'key')::uuid;
 if key is null then raise exception 'Request key required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,991));
 select * into t from support.tickets where user_id=uid and request_key=key;
 if found then return jsonb_build_object('id',t.id,'number',t.number);end if;
 if (select count(*) from support.tickets where user_id=uid and created_at>now()-interval '1 hour')>=5 then raise exception 'Too many new tickets. Reply to an existing ticket / Jibu kwenye ticket iliyopo';end if;
 v_subject:=btrim(p_payload->>'subject');body:=btrim(p_payload->>'body');cat:=p_payload->>'category';pid:=nullif(p_payload->>'purchase_id','')::uuid;
 if v_subject is null or length(v_subject) not between 5 and 140 or body is null or length(body) not between 10 and 2000 or cat is null or cat not in ('account','technical','general','payment','content','refund') then raise exception 'Check the subject, category and message / Kagua kichwa, aina na maelezo';end if;
 if pid is not null and not exists(select 1 from public.purchases where id=pid and user_id=uid) then raise exception 'Purchase unavailable / Ununuzi haupatikani';end if;
 if pid is not null and cat not in ('payment','content','refund') then raise exception 'Use a purchase category / Chagua aina ya tatizo la ununuzi';end if;
 if pid is not null then
 select * into t from support.tickets where user_id=uid and purchase_id=pid and category=cat and status not in ('resolved','closed') order by created_at limit 1;
 if found then return jsonb_build_object('id',t.id,'number',t.number,'existing',true);end if;
 end if;
 if cat='refund' then
 if pid is null or not exists(select 1 from public.purchases where id=pid and user_id=uid and payment_status in ('paid','submitted','refunded')) then raise exception 'Select a submitted or paid purchase / Chagua ununuzi uliolipwa au uliowasilishwa';end if;
 select t2.* into t from support.tickets t2 where t2.purchase_id=pid and dispute_id is not null;
 if found then return jsonb_build_object('id',t.id,'number',t.number,'existing',true);end if;
 insert into public.disputes(user_id,purchase_id,reason,details) values(uid,pid,'other',body) returning id into rid;
 select id into tid from support.tickets where dispute_id=rid;
 update support.tickets set subject=v_subject,request_key=key,email_updates=coalesce((p_payload->>'email_updates')::boolean,false) where id=tid;
 else
 insert into support.tickets(user_id,subject,category,purchase_id,request_key,email_updates,assigned_to,due_at)
 values(uid,v_subject,cat,pid,key,coalesce((p_payload->>'email_updates')::boolean,false),support.assign(cat),support.due(cat)) returning id into tid;
 insert into support.messages(ticket_id,author_id,kind,body,request_key) values(tid,uid,'customer',body,key);
 perform support.notify_agent(tid);
 end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id) values(uid,'support_created','support_ticket',tid::text);
 perform support.notify_customer(tid,tid::text);
 return (select jsonb_build_object('id',id,'number',number) from support.tickets where id=tid);
 elsif p_action='agents' then
 if not admin_alerts.is_superadmin() then raise exception 'Superadmin required';end if;
 if p_payload ? 'email' then
 if length(btrim(coalesce(p_payload->>'reason','')))<10 then raise exception 'Access reason required';end if;
 select id into agent from auth.users where lower(email)=lower(btrim(p_payload->>'email')) and email_confirmed_at is not null;
 if agent is null then raise exception 'Verified registered account required / Akaunti iliyosajiliwa na kuthibitishwa inahitajika';end if;
 insert into support.agents(user_id,enabled) values(agent,coalesce((p_payload->>'enabled')::boolean,false)) on conflict(user_id) do update set enabled=excluded.enabled;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(uid,'staff_permissions','support_agent',agent::text,jsonb_build_object('enabled',p_payload->'enabled','reason',left(p_payload->>'reason',500)));
 end if;
 return coalesce((select jsonb_agg(x) from (select a.user_id,a.enabled,p.full_name from support.agents a join public.profiles p on p.id=a.user_id) x),'[]');
 end if;

 tid:=(p_payload->>'id')::uuid;
 select * into t from support.tickets where id=tid for update;
 if not found or (not team and t.user_id<>uid) or (team and not support.eligible(uid,t.category)) then raise exception 'Ticket unavailable / Ticket haipatikani';end if;
 if p_action='get' then
 if team then insert into public.audit_logs(actor_user_id,action,entity_type,entity_id) values(uid,'support_ticket_read','support_ticket',tid::text);end if;
 return jsonb_build_object('ticket',to_jsonb(t)-'request_key','messages',coalesce((select jsonb_agg(to_jsonb(m)-'request_key'-'author_id' order by m.created_at,m.id) from support.messages m where m.ticket_id=tid and (team or not m.internal)),'[]'),
 'dispute',case when t.dispute_id is not null then (select jsonb_build_object('id',id,'status',status,'resolution',resolution,'refund_reference',refund_reference) from public.disputes where id=t.dispute_id) end);
 elsif p_action='email' and not team then
 update support.tickets set email_updates=coalesce((p_payload->>'enabled')::boolean,false) where id=tid;
 return jsonb_build_object('ok',true);
 elsif p_action='reply' then
 if t.redacted_at is not null then raise exception 'Ticket archived / Ticket imehifadhiwa';end if;
 key:=(p_payload->>'key')::uuid;body:=btrim(p_payload->>'body');internal_note:=team and coalesce((p_payload->>'internal')::boolean,false);
 if key is null or body is null or length(body) not between 1 and 4000 then raise exception 'Message required, maximum 4000 characters';end if;
 if not team and coalesce((p_payload->>'internal')::boolean,false) then raise exception 'Staff-only note';end if;
 if exists(select 1 from support.messages where ticket_id=tid and author_id=uid and request_key=key) then return jsonb_build_object('ok',true);end if;
 if (select count(*) from support.messages where author_id=uid and created_at>now()-interval '1 minute')>=10 then raise exception 'Please wait before sending again / Subiri kabla ya kutuma tena';end if;
 st:=case when team then coalesce(p_payload->>'status','waiting_customer') else 'open' end;
 if st not in ('open','in_progress','waiting_customer','resolved','closed') then raise exception 'Invalid status';end if;
 if not internal_note and st in ('resolved','closed') and length(body)<10 then raise exception 'Explain the resolution / Eleza suluhisho';end if;
 if not internal_note and st in ('resolved','closed') and exists(select 1 from public.disputes where id=t.dispute_id and status in ('open','approved')) then raise exception 'Finance review or transfer still pending / Ukaguzi wa fedha au marejesho bado';end if;
 insert into support.messages(ticket_id,author_id,kind,internal,body,request_key) values(tid,uid,case when team then 'staff' else 'customer' end,internal_note,body,key) returning id into mid;
 if not internal_note then
 update support.tickets set status=st,updated_at=now(),due_at=case when st in ('open','in_progress') then support.due(category) end,escalated_at=null where id=tid;
 if team then perform support.notify_customer(tid,mid::text);else perform support.notify_agent(tid);end if;
 end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(uid,'support_reply','support_ticket',tid::text,jsonb_build_object('internal',internal_note,'message_id',mid,'status',case when internal_note then t.status else st end));
 return jsonb_build_object('ok',true);
 elsif p_action='assign' and team then
 agent:=nullif(p_payload->>'agent','')::uuid;
 if agent is not null and not support.eligible(agent,t.category) then raise exception 'Eligible support agent required';end if;
 update support.tickets set assigned_to=agent,updated_at=now() where id=tid;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(uid,'support_assigned','support_ticket',tid::text,jsonb_build_object('assigned_to',agent));
 perform support.notify_agent(tid);return jsonb_build_object('ok',true);
 end if;
 raise exception 'Unsupported support action';
end $$;
create function public.support_api(p_action text,p_payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select support.api(p_action,p_payload);$$;
revoke all on all functions in schema support from public,anon,authenticated,service_role;
grant execute on function support.api(text,jsonb) to authenticated;
revoke all on function public.support_api(text,jsonb) from public,anon,authenticated;
grant execute on function public.support_api(text,jsonb) to authenticated;

create function support.escalate() returns void language plpgsql security definer set search_path='' as $$
declare t support.tickets;
begin
 for t in select * from support.tickets where status in ('open','in_progress') and due_at<=now() and escalated_at is null for update skip locked loop
 update support.tickets set escalated_at=now() where id=t.id;
 insert into admin_alerts.outbox(event_key,kind) values('support-overdue/'||t.id||'/'||t.due_at,'support_escalation') on conflict do nothing;
 perform support.notify_agent(t.id);
 insert into public.audit_logs(action,entity_type,entity_id) values('support_escalated','support_ticket',t.id::text);
 end loop;
end $$;
revoke all on function support.escalate() from public,anon,authenticated,service_role;
select cron.schedule('betslip-support-escalation','15 * * * *','select support.escalate();');

-- Customer payloads may only be delivered to the current confirmed account address.
create function support.email_allowed(p_summary jsonb) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from support.tickets t join auth.users u on u.id=t.user_id join public.profiles p on p.id=u.id
 where t.id::text=p_summary->>'ticket_id' and t.email_updates and t.redacted_at is null and u.email_confirmed_at is not null and u.email=p_summary->>'email' and p.status='active');
$$;
revoke all on function support.email_allowed(jsonb) from public,anon,authenticated,service_role;
do $$declare definition text;begin
 definition:=pg_get_functiondef('admin_alerts.claim(text,boolean)'::regprocedure);
 definition:=replace(definition,'with candidates as (','update admin_alerts.outbox set status=''failed'',error_code=''recipient_unavailable'',lease_token=null,lease_until=null where kind=''support_customer'' and status in (''pending'',''sending'') and not support.email_allowed(summary);'||chr(10)||' with candidates as (');
 execute definition;
end $$;
-- Include customer-visible support history in the existing access/export control.
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.export_my_data()'::regprocedure);
 definition:=replace(definition,'return result;', 'return result || jsonb_build_object(''support_tickets'',coalesce((select jsonb_agg(to_jsonb(t)-''request_key'') from support.tickets t where user_id=auth.uid()),''[]''),''support_messages'',coalesce((select jsonb_agg(to_jsonb(m)-''request_key''-''author_id'') from support.messages m join support.tickets t on t.id=m.ticket_id where t.user_id=auth.uid() and not m.internal),''[]''));');
 execute definition;
end $$;
commit;
