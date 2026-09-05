begin;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create function admin_alerts.dispatch() returns bigint language plpgsql security definer set search_path='' as $$
declare request_id bigint;
begin
 select net.http_post(
 url:='https://iqdgtnwgphqstpazquku.supabase.co/functions/v1/admin-alerts',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='betslip_admin_alerts_worker')),
 body:='{}'::jsonb,timeout_milliseconds:=55000
 ) into request_id;
 return request_id;
end $$;
revoke all on function admin_alerts.dispatch() from public,anon,authenticated,service_role;
select cron.schedule('betslip-important-admin-alerts','*/2 * * * *','select admin_alerts.dispatch();');
commit;
