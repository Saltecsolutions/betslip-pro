begin;
create schema admin_alerts;
revoke all on schema admin_alerts from public,anon;
grant usage on schema admin_alerts to authenticated,service_role;
create table admin_alerts.settings (
 id boolean primary key default true check(id), enabled boolean not null default true,
 recipient text not null default 'salmin@saltecsolutions.co.tz' check(recipient='salmin@saltecsolutions.co.tz'),
 last_worker_at timestamptz, worker_status text not null default 'not_started'
);
insert into admin_alerts.settings(id) values(true);
create table admin_alerts.outbox (
 id uuid primary key default gen_random_uuid(), event_key text not null unique,
 kind text not null check(kind in ('partnership','privacy','permissions','dispute','payment_failed','integrity','test')),
 status text not null default 'pending' check(status in ('pending','sending','accepted','failed')),
 created_at timestamptz not null default now(), first_attempt_at timestamptz,
 next_attempt_at timestamptz not null default now(), lease_until timestamptz, lease_token uuid,
 attempts integer not null default 0, provider_id text, error_code text, accepted_at timestamptz
);
create index on admin_alerts.outbox(next_attempt_at) where status in ('pending','sending');
alter table admin_alerts.settings enable row level security;
alter table admin_alerts.outbox enable row level security;
revoke all on all tables in schema admin_alerts from public,anon,authenticated,service_role;
-- Trigger-only enqueue: no user text, identity, payment reference or KYC payload leaves the database.
create function admin_alerts.capture_audit() returns trigger language plpgsql security definer set search_path='' as $$
declare k text;
begin
 k:=case new.action when 'partnership_requested' then 'partnership' when 'privacy_request' then 'privacy' when 'staff_permissions' then 'permissions' when 'tipster_integrity_review' then 'integrity' else null end;
 if new.action='record_updated' and new.entity_type='profiles' and new.metadata->'changed_fields' ? 'role' then k:='permissions';end if;
 if k is not null then insert into admin_alerts.outbox(event_key,kind) values('audit/'||new.id,k) on conflict do nothing;end if;
 return new;
end $$;
create trigger important_admin_audit after insert on public.audit_logs for each row execute function admin_alerts.capture_audit();
create function admin_alerts.capture_dispute() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into admin_alerts.outbox(event_key,kind) values('dispute/'||new.id,'dispute') on conflict do nothing;return new;end $$;
create trigger important_admin_dispute after insert on public.disputes for each row execute function admin_alerts.capture_dispute();
create function admin_alerts.capture_payment() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.payment_status='failed' and old.payment_status is distinct from new.payment_status then
 insert into admin_alerts.outbox(event_key,kind) values('payment_failed/'||new.id,'payment_failed') on conflict do nothing;end if;return new;
end $$;
create trigger important_admin_payment after update on public.purchases for each row execute function admin_alerts.capture_payment();
create function admin_alerts.is_superadmin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and role='super_admin' and status='active');
$$;
create function admin_alerts.manage(p_action text,p_enabled boolean default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not admin_alerts.is_superadmin() then raise exception 'Active superadmin required';end if;
 if p_action='toggle' then
 if p_enabled is null then raise exception 'Enabled required';end if;
 update admin_alerts.settings set enabled=p_enabled where id=true;
 elsif p_action='test' then
 perform pg_advisory_xact_lock(925510);
 if exists(select 1 from admin_alerts.outbox where kind='test' and created_at>now()-interval '10 minutes') then raise exception 'Wait ten minutes between tests';end if;
 insert into admin_alerts.outbox(event_key,kind) values('test/'||gen_random_uuid(),'test');
 elsif p_action<>'read' or p_action is null then raise exception 'Invalid action';end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(auth.uid(),'admin_alerts_'||p_action,'configuration',jsonb_build_object('enabled',p_enabled));
 select jsonb_build_object('settings',(select to_jsonb(s) from admin_alerts.settings s),'counts',(select jsonb_object_agg(status,n) from (select status,count(*) n from admin_alerts.outbox group by status) c),'items',coalesce((select jsonb_agg(r order by r.created_at desc) from (select id,kind,status,created_at,attempts,error_code,accepted_at from admin_alerts.outbox order by created_at desc limit 50) r),'[]'::jsonb)) into result;
 return result;
end $$;
create function public.admin_alerts_manage(p_action text,p_enabled boolean default null) returns jsonb language sql security invoker set search_path='' as $$select admin_alerts.manage(p_action,p_enabled);$$;
-- The worker token is generated inside Vault and never sent to the frontend or source repository.
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'betslip_admin_alerts_worker');
create function admin_alerts.claim(p_token text,p_configured boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if p_token is null or length(p_token)<>64 or not exists(select 1 from vault.decrypted_secrets where name='betslip_admin_alerts_worker' and decrypted_secret=p_token) then raise exception 'Invalid worker token';end if;
 update admin_alerts.settings set last_worker_at=now(),worker_status=case when not enabled then 'paused' when p_configured then 'ready' else 'missing_resend_key' end where id=true;
 if not p_configured or not (select enabled from admin_alerts.settings) then return '[]';end if;
 -- Stop automatic retries before Resend's 24-hour idempotency window expires.
 update admin_alerts.outbox set status='failed',error_code='retry_window_expired',lease_token=null,lease_until=null where status in ('pending','sending') and first_attempt_at<now()-interval '20 hours';
 update admin_alerts.outbox set status='failed',error_code='attempt_limit',lease_token=null,lease_until=null where status='sending' and lease_until<now() and attempts>=6;
 with candidates as (select id from admin_alerts.outbox where attempts<6 and ((status='pending' and next_attempt_at<=now()) or (status='sending' and lease_until<now())) order by created_at for update skip locked limit 5), claimed as (
 update admin_alerts.outbox o set status='sending',attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()),lease_until=now()+interval '5 minutes',lease_token=gen_random_uuid() from candidates c where o.id=c.id returning o.id,o.kind,o.lease_token
 ) select coalesce(jsonb_agg(c),'[]') into result from claimed c;
 return result;
end $$;
create function admin_alerts.finish(p_id uuid,p_lease uuid,p_provider_id text,p_error text,p_retry boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_provider_id is not null and length(p_provider_id)>128 then raise exception 'Invalid provider ID';end if;
 update admin_alerts.outbox set status=case when p_provider_id is not null then 'accepted' when p_retry and attempts<6 then 'pending' else 'failed' end,
 provider_id=p_provider_id,accepted_at=case when p_provider_id is not null then now() end,
 error_code=left(p_error,80),next_attempt_at=now()+make_interval(secs=>least(3600,60*power(2,attempts)::integer)),lease_until=null,lease_token=null
 where id=p_id and status='sending' and lease_token=p_lease;
 return found;
end $$;
create function public.admin_alerts_claim(p_token text,p_configured boolean) returns jsonb language sql security invoker set search_path='' as $$select admin_alerts.claim(p_token,p_configured);$$;
create function public.admin_alerts_finish(p_id uuid,p_lease uuid,p_provider_id text,p_error text,p_retry boolean) returns boolean language sql security invoker set search_path='' as $$select admin_alerts.finish(p_id,p_lease,p_provider_id,p_error,p_retry);$$;
revoke all on all functions in schema admin_alerts from public,anon,authenticated,service_role;
grant execute on function admin_alerts.manage(text,boolean) to authenticated;
grant execute on function admin_alerts.claim(text,boolean),admin_alerts.finish(uuid,uuid,text,text,boolean) to service_role;
revoke all on function public.admin_alerts_manage(text,boolean),public.admin_alerts_claim(text,boolean),public.admin_alerts_finish(uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.admin_alerts_manage(text,boolean) to authenticated;
grant execute on function public.admin_alerts_claim(text,boolean),public.admin_alerts_finish(uuid,uuid,text,text,boolean) to service_role;
commit;
