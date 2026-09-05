begin;
alter table admin_alerts.outbox drop constraint outbox_kind_check;
alter table admin_alerts.outbox add constraint outbox_kind_check check(kind in ('partnership','privacy','permissions','dispute','payment_failed','integrity','test','partner_weekly'));
alter table admin_alerts.outbox add column summary jsonb;
alter table admin_alerts.settings add column partner_enabled boolean not null default true;
-- Only this fixed, aggregate-only report is routed to the partner by the worker.
create function admin_alerts.enqueue_partner_weekly() returns void language plpgsql security definer set search_path='' as $$
declare until_at timestamptz; since_at timestamptz; snapshot jsonb;
begin
 if not (select partner_enabled from admin_alerts.settings where id=true) then return;end if;
 until_at:=date_trunc('week',now() at time zone 'Africa/Dar_es_Salaam') at time zone 'Africa/Dar_es_Salaam';
 since_at:=until_at-interval '7 days';
 select jsonb_build_object(
 'period_start',(since_at at time zone 'Africa/Dar_es_Salaam')::date,
 'period_end',((until_at at time zone 'Africa/Dar_es_Salaam')::date-1),
 'new_users',(select count(*) from public.profiles where created_at>=since_at and created_at<until_at and role not in ('admin','super_admin')),
 'publishing_tipsters',(select count(distinct tipster_id) from public.predictions where published_at>=since_at and published_at<until_at),
 'published_content',(select count(*) from public.predictions where published_at>=since_at and published_at<until_at),
 'paid_purchases',(select count(*) from public.purchases where payment_verified_at>=since_at and payment_verified_at<until_at and payment_status='paid'),
 'partnership_requests',(select count(*) from partnerships.requests where created_at>=since_at and created_at<until_at)
 ) into snapshot;
 insert into admin_alerts.outbox(event_key,kind,summary) values('partner-weekly/'||(until_at at time zone 'Africa/Dar_es_Salaam')::date,'partner_weekly',snapshot) on conflict(event_key) do nothing;
end $$;
revoke all on function admin_alerts.enqueue_partner_weekly() from public,anon,authenticated,service_role;
-- pg_cron uses UTC: Monday 06:00 UTC = 09:00 Africa/Dar_es_Salaam.
select cron.schedule('betslip-partner-weekly','0 6 * * 1','select admin_alerts.enqueue_partner_weekly();');
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
 update admin_alerts.outbox o set status='sending',attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()),lease_until=now()+interval '5 minutes',lease_token=gen_random_uuid() from candidates c where o.id=c.id returning o.id,o.kind,o.lease_token,o.summary
 ) select coalesce(jsonb_agg(c),'[]') into result from claimed c;
 return result;
end $$;
create or replace function admin_alerts.manage(p_action text,p_enabled boolean default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not admin_alerts.is_superadmin() then raise exception 'Active superadmin required';end if;
 if p_action='toggle' then
 if p_enabled is null then raise exception 'Enabled required';end if;
 update admin_alerts.settings set enabled=p_enabled where id=true;
 elsif p_action='partner_toggle' then
 if p_enabled is null then raise exception 'Enabled required';end if;
 update admin_alerts.settings set partner_enabled=p_enabled where id=true;
 elsif p_action='test' then
 perform pg_advisory_xact_lock(925510);
 if exists(select 1 from admin_alerts.outbox where kind='test' and created_at>now()-interval '10 minutes') then raise exception 'Wait ten minutes between tests';end if;
 insert into admin_alerts.outbox(event_key,kind) values('test/'||gen_random_uuid(),'test');
 elsif p_action<>'read' or p_action is null then raise exception 'Invalid action';end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(auth.uid(),'admin_alerts_'||p_action,'configuration',jsonb_build_object('enabled',p_enabled));
 select jsonb_build_object('settings',(select to_jsonb(s) from admin_alerts.settings s),'counts',(select jsonb_object_agg(status,n) from (select status,count(*) n from admin_alerts.outbox group by status) c),'items',coalesce((select jsonb_agg(r order by r.created_at desc) from (select id,kind,status,created_at,attempts,error_code,accepted_at from admin_alerts.outbox order by created_at desc limit 50) r),'[]'::jsonb)) into result;
 return result;
end $$;
commit;
