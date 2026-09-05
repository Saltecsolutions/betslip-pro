begin;
create or replace function admin_alerts.manage(p_action text,p_enabled boolean default null) returns jsonb language plpgsql security definer set search_path='' as $$
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
create or replace function admin_alerts.claim(p_token text,p_configured boolean) returns jsonb language plpgsql security definer set search_path='' as $$
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
commit;
