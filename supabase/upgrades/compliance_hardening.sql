begin;
drop policy disputes_read on public.disputes;
create policy disputes_read on public.disputes for select to authenticated using(user_id=(select auth.uid()));
-- Keep privileged implementations out of the exposed schema; public RPCs are invoker wrappers.
DO $block$ declare r record; args text; names text; rettype text; begin
 for r in select * from pg_proc where pronamespace='public'::regnamespace and proname in ('compliance_access','accept_policies','policy_status','request_privacy','export_my_data','admin_compliance_read','admin_compliance_setting','admin_privacy_review','admin_restrict_account','admin_staff_access','admin_kyc_reference','admin_retention_cleanup') loop
 args:=pg_get_function_arguments(r.oid);rettype:=pg_get_function_result(r.oid);names:=coalesce(array_to_string(r.proargnames,','),'');
 execute format('alter function public.%I(%s) set schema compliance',r.proname,pg_get_function_identity_arguments(r.oid));
 execute format('create function public.%I(%s) returns %s language sql security invoker set search_path='''' as %L',r.proname,args,rettype,'select compliance.'||r.proname||'('||names||');');
 execute format('revoke all on function public.%I(%s) from public,anon,authenticated',r.proname,pg_get_function_identity_arguments(r.oid));
 execute format('grant execute on function public.%I(%s) to authenticated',r.proname,pg_get_function_identity_arguments(r.oid));
 end loop;
end $block$;
-- Validate declared retention and operator information before recording confirmation.
create function compliance.validate_configuration() returns trigger language plpgsql set search_path='' as $$
begin
 if new.value->>'status'='confirmed' then
 if new.key='retention' and length(btrim(coalesce(new.value->>'schedule','')))<20 then raise exception 'Document the retention schedule and legal holds';end if;
 if new.key='operator' and (length(btrim(coalesce(new.value->>'legal_name','')))<2 or position('@' in coalesce(new.value->>'privacy_contact',''))<2 or length(btrim(coalesce(new.value->>'address','')))<5) then raise exception 'Operator name, privacy contact and address required';end if;
 if new.key='tax' and (nullif(btrim(new.value->>'rate'),'') is null or nullif(btrim(new.value->>'base'),'') is null or nullif(btrim(new.value->>'gross_up'),'') is null) then raise exception 'Document confirmed rate, base and gross-up treatment';end if;
 end if;return new;
end $$;
create trigger configuration_validation before update on compliance.settings for each row execute function compliance.validate_configuration();
revoke all on function compliance.validate_configuration() from public,anon,authenticated;
create function compliance.operator_contact() returns jsonb language sql stable security definer set search_path='' as $$ select case when value->>'status'='confirmed' then jsonb_build_object('legal_name',value->>'legal_name','privacy_contact',value->>'privacy_contact','address',value->>'address') else '{}'::jsonb end from compliance.settings where key='operator'; $$;
create function public.operator_contact() returns jsonb language sql security invoker set search_path='' as $$ select compliance.operator_contact(); $$;
revoke all on function compliance.operator_contact(),public.operator_contact() from public,anon,authenticated;
grant usage on schema compliance to anon;
grant execute on function compliance.operator_contact(),public.operator_contact() to anon,authenticated;
-- A restricted user cannot replace their previously public profile image.
drop policy tipster_profile_update on storage.objects;
create policy tipster_profile_update on storage.objects for update to authenticated using(bucket_id='tipster-profiles' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles where id=auth.uid() and status='active')) with check(bucket_id='tipster-profiles' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles where id=auth.uid() and status='active'));
commit;
