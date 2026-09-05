begin;
select admin_alerts.enqueue_partner_weekly();
select admin_alerts.enqueue_partner_weekly();
do $$declare report jsonb; boundary date; begin
 boundary:=date_trunc('week',now() at time zone 'Africa/Dar_es_Salaam')::date;
 if (select count(*) from admin_alerts.outbox where event_key='partner-weekly/'||boundary)<>1 then raise exception 'FAIL weekly deduplication';end if;
 select summary into report from admin_alerts.outbox where event_key='partner-weekly/'||boundary;
 if report->>'period_start'<>(boundary-7)::text or report->>'period_end'<>(boundary-1)::text then raise exception 'FAIL calendar week boundary';end if;
 if (select count(*) from jsonb_object_keys(report))<>7 then raise exception 'FAIL unexpected report data';end if;
 if has_function_privilege('anon','admin_alerts.enqueue_partner_weekly()','execute') or has_function_privilege('authenticated','admin_alerts.enqueue_partner_weekly()','execute') then raise exception 'FAIL public report access';end if;
 update admin_alerts.settings set partner_enabled=false where id=true;
 perform admin_alerts.enqueue_partner_weekly();
 if (select count(*) from admin_alerts.outbox where event_key='partner-weekly/'||boundary)<>1 then raise exception 'FAIL paused report';end if;
end $$;
select 'PASS: snapshot generation, calendar week, deduplication, fixed fields and authorization' as result;
rollback;
