begin;
create schema if not exists compliance;
revoke all on schema compliance from public,anon,authenticated;
create table compliance.staff_access(user_id uuid primary key references public.profiles(id), privacy boolean not null default false, finance boolean not null default false, kyc boolean not null default false, configuration boolean not null default false);
create table compliance.settings(key text primary key, value jsonb not null, updated_at timestamptz not null default now(), updated_by uuid references public.profiles(id));
insert into compliance.settings values
('pdpc','{"status":"unconfirmed","reference":""}',now(),null),
('gaming_board','{"status":"unconfirmed","reference":""}',now(),null),
('tax','{"status":"unconfirmed","reference":"","rate":null,"base":null,"gross_up":null}',now(),null),
('retention','{"status":"unconfirmed","reference":"","financial_days":null,"kyc_days":null,"audit_days":null}',now(),null),
('operator','{"status":"unconfirmed","reference":"","legal_name":"","privacy_contact":"","address":""}',now(),null);
create table compliance.kyc_records(user_id uuid primary key references public.profiles(id), provider_reference text not null, review_status text not null check(review_status in ('pending','verified','rejected')), retain_until timestamptz, legal_hold boolean not null default false, updated_at timestamptz not null default now());
-- Store provider references only: raw identity documents do not belong in public storage.
create table public.policy_acceptances(user_id uuid not null references public.profiles(id), document text not null check(document in ('terms','privacy','seller','adult')), version text not null, locale text not null check(locale in ('en','sw')), accepted_at timestamptz not null default now(), primary key(user_id,document,version));
create table public.privacy_requests(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),kind text not null check(kind in ('access','correction','deletion')),details text not null check(length(details) between 10 and 2000),status text not null default 'open' check(status in ('open','reviewing','completed','partially_completed','rejected')),resolution text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index one_open_privacy_request on public.privacy_requests(user_id,kind) where status in ('open','reviewing');
alter table public.policy_acceptances enable row level security;
alter table public.privacy_requests enable row level security;
alter table compliance.staff_access enable row level security;
alter table compliance.settings enable row level security;
alter table compliance.kyc_records enable row level security;
revoke all on public.policy_acceptances,public.privacy_requests from public,anon,authenticated;
grant select on public.policy_acceptances,public.privacy_requests to authenticated;
create policy acceptances_own on public.policy_acceptances for select to authenticated using(user_id=(select auth.uid()));
create policy privacy_own on public.privacy_requests for select to authenticated using(user_id=(select auth.uid()));
create trigger acceptance_append_only before update or delete on public.policy_acceptances for each row execute function public.guard_evidence();
create function compliance.can(p_scope text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and (p.role='super_admin' or (p.role='admin' and exists(select 1 from compliance.staff_access a where a.user_id=p.id and case p_scope when 'privacy' then a.privacy when 'finance' then a.finance when 'kyc' then a.kyc when 'configuration' then a.configuration else false end))));
$$;
create function public.compliance_access() returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_build_object('privacy',compliance.can('privacy'),'finance',compliance.can('finance'),'kyc',compliance.can('kyc'),'configuration',compliance.can('configuration')); $$;
create function public.accept_policies(p_version text,p_locale text,p_seller boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and (email_confirmed_at is not null or phone_confirmed_at is not null)) then raise exception 'Verified sign-in required'; end if;
 if p_version is distinct from '2026-09-05' or p_locale not in ('en','sw') or p_locale is null or p_seller is null then raise exception 'Reload current policies'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'Active account required'; end if;
 insert into public.policy_acceptances(user_id,document,version,locale) select auth.uid(),d,p_version,p_locale from unnest(case when p_seller then array['terms','privacy','adult','seller'] else array['terms','privacy','adult'] end) d on conflict do nothing;
 update public.profiles set age_verified=true where id=auth.uid();
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'policies_accepted','account',auth.uid()::text,jsonb_build_object('version',p_version,'seller',p_seller));
end $$;
create function compliance.accepted(p_user uuid,p_seller boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=p_user and status='active') and (select count(*) from public.policy_acceptances where user_id=p_user and version='2026-09-05' and document=any(case when p_seller then array['terms','privacy','adult','seller'] else array['terms','privacy','adult'] end))=case when p_seller then 4 else 3 end;
$$;
create function public.policy_status() returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_build_object('accepted',coalesce(compliance.accepted(auth.uid()),false),'seller',coalesce(compliance.accepted(auth.uid(),true),false),'version','2026-09-05'); $$;
create function compliance.gate_transactions() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 if TG_TABLE_NAME='purchases' then
   if not compliance.accepted(new.user_id) then raise exception 'Accept current Terms, Privacy and 18+ notice in Account / Privacy'; end if;
 elsif TG_TABLE_NAME='predictions' then
   select user_id into uid from public.tipsters where id=new.tipster_id;
   if (TG_OP='INSERT' or (new.status='published' and old.status<>'published')) and not compliance.accepted(uid,true) then raise exception 'Seller must accept current Tipster Agreement in Account / Privacy'; end if;
 end if; return new;
end $$;
create trigger purchase_consent before insert on public.purchases for each row execute function compliance.gate_transactions();
create trigger seller_consent before insert or update on public.predictions for each row execute function compliance.gate_transactions();
create function public.request_privacy(p_kind text,p_details text) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.privacy_requests(user_id,kind,details) values(auth.uid(),p_kind,btrim(p_details)) returning id into rid;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'privacy_request','privacy_request',rid::text,jsonb_build_object('kind',p_kind)); return rid;
end $$;
create function public.export_my_data() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where id=auth.uid()),'purchases',coalesce((select jsonb_agg(to_jsonb(p)-'payment_proof_note') from public.purchases p where user_id=auth.uid()),'[]'),'ledger',coalesce((select jsonb_agg(to_jsonb(l)-'metadata') from public.ledger_entries l where user_id=auth.uid()),'[]'),'acceptances',coalesce((select jsonb_agg(a) from public.policy_acceptances a where user_id=auth.uid()),'[]'),'requests',coalesce((select jsonb_agg(r) from public.privacy_requests r where user_id=auth.uid()),'[]')) into result;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id) values(auth.uid(),'self_data_export','account',auth.uid()::text); return result;
end $$;
create function public.admin_compliance_read(p_area text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; scope text;
begin
 scope:=case p_area when 'requests' then 'privacy' when 'accounts' then 'privacy' when 'kyc' then 'kyc' when 'settings' then 'configuration' when 'audit' then 'privacy' when 'payments' then 'finance' when 'disputes' then 'finance' end;
 if scope is null or not compliance.can(scope) or length(btrim(coalesce(p_reason,'')))<10 then raise exception 'Assigned permission and access reason required'; end if;
 case p_area
 when 'payments' then select coalesce(jsonb_agg(r),'[]') into result from (select id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_reference,payment_status,processing_fee_tzs from public.purchases where payment_status in ('submitted','paid') order by created_at desc limit 200) r;
 when 'disputes' then select coalesce(jsonb_agg(r),'[]') into result from (select * from public.disputes order by created_at desc limit 200) r;
 when 'requests' then select coalesce(jsonb_agg(r),'[]') into result from (select * from public.privacy_requests order by created_at desc limit 200) r;
 when 'accounts' then select coalesce(jsonb_agg(r),'[]') into result from (select id,full_name,phone,status from public.profiles order by created_at desc limit 200) r;
 when 'kyc' then select coalesce(jsonb_agg(r),'[]') into result from compliance.kyc_records r;
 when 'settings' then select coalesce(jsonb_agg(r),'[]') into result from compliance.settings r;
 when 'audit' then select coalesce(jsonb_agg(r),'[]') into result from (select * from public.audit_logs order by created_at desc limit 200) r;
 end case;
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(auth.uid(),'restricted_read',p_area,jsonb_build_object('reason',p_reason)); return result;
end $$;
create function public.admin_compliance_setting(p_key text,p_value jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not compliance.can('configuration') then raise exception 'Configuration permission required'; end if;
 if length(btrim(coalesce(p_reason,'')))<10 or jsonb_typeof(p_value)<>'object' or coalesce(p_value->>'status','') not in ('unconfirmed','in_review','confirmed','not_applicable') then raise exception 'Status and reason required'; end if;
 if p_value->>'status' in ('confirmed','not_applicable') and length(btrim(coalesce(p_value->>'reference','')))<10 then raise exception 'Documented confirmation reference required'; end if;
 update compliance.settings set value=p_value,updated_at=now(),updated_by=auth.uid() where key=p_key;
 if not found then raise exception 'Unknown setting'; end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'compliance_setting','configuration',p_key,jsonb_build_object('value',p_value,'reason',p_reason));
end $$;
create function public.admin_privacy_review(p_id uuid,p_status text,p_resolution text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not compliance.can('privacy') then raise exception 'Privacy permission required'; end if;
 if length(btrim(coalesce(p_resolution,'')))<20 then raise exception 'Resolution and retained-record explanation required'; end if;
 update public.privacy_requests set status=p_status,resolution=p_resolution,updated_at=now() where id=p_id and status in ('open','reviewing');
 if not found then raise exception 'Open request required'; end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'privacy_review','privacy_request',p_id::text,jsonb_build_object('status',p_status,'resolution',p_resolution));
end $$;
create function public.admin_restrict_account(p_request uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 if not compliance.can('privacy') or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'Privacy permission and retention reason required'; end if;
 select user_id into uid from public.privacy_requests where id=p_request and kind='deletion' and status in ('open','reviewing') for update;
 if uid is null or exists(select 1 from public.profiles where id=uid and role in ('admin','super_admin')) then raise exception 'Eligible deletion request required'; end if;
 -- Retain the pseudonymous parent to protect purchases, ledger, audit and immutable slips.
 update public.profiles set full_name='Closed account',phone=null,status='suspended' where id=uid;
 update public.tipsters set display_name='Former tipster',bio=null,profile_image_url=null,location=null where user_id=uid;
 delete from public.tipster_follows where user_id=uid;
 delete from public.notifications where user_id=uid;
 delete from auth.sessions where user_id=uid;
 update public.privacy_requests set status='reviewing',resolution=p_reason,updated_at=now() where id=p_request;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'account_restricted','account',uid::text,jsonb_build_object('request',p_request,'reason',p_reason));
end $$;
create function public.admin_staff_access(p_user uuid,p_privacy boolean,p_finance boolean,p_kyc boolean,p_configuration boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='super_admin' and status='active') or length(btrim(coalesce(p_reason,'')))<10 then raise exception 'Super admin and reason required'; end if;
 if not exists(select 1 from public.profiles where id=p_user and role='admin' and status='active') then raise exception 'Active admin required'; end if;
 insert into compliance.staff_access values(p_user,p_privacy,p_finance,p_kyc,p_configuration) on conflict(user_id) do update set privacy=excluded.privacy,finance=excluded.finance,kyc=excluded.kyc,configuration=excluded.configuration;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'staff_permissions','account',p_user::text,jsonb_build_object('privacy',p_privacy,'finance',p_finance,'kyc',p_kyc,'configuration',p_configuration,'reason',p_reason));
end $$;
-- Private account data and audit evidence are only read by owners or audited RPCs.
drop policy if exists admin_profiles_all on public.profiles;
drop policy if exists audit_admin_read on public.audit_logs;
drop policy if exists admin_purchases_all on public.purchases;

drop policy if exists ledger_read on public.ledger_entries;
create policy ledger_read on public.ledger_entries for select to authenticated using(user_id=auth.uid());
drop policy if exists withdrawals_read on public.withdrawals;
create policy withdrawals_read on public.withdrawals for select to authenticated using(exists(select 1 from public.tipsters where id=tipster_id and user_id=auth.uid()));
-- Existing finance RPCs must require finance permission, not generic moderation access.
DO $block$ declare r record; definition text; begin
 for r in select oid from pg_proc where pronamespace='public'::regnamespace and proname in ('admin_verify_manual_payment','make_tipster_earnings_available','admin_resolve_dispute') loop
 definition:=pg_get_functiondef(r.oid); definition:=replace(definition,'public.is_admin()','compliance.can(''finance'')'); definition:=replace(definition,'begin'||chr(10),'begin'||chr(10)||' if not compliance.can(''finance'') then raise exception ''Finance permission required''; end if;'||chr(10)); execute definition;
 end loop;
end $block$;
grant usage on schema compliance to authenticated;
grant execute on function compliance.can(text) to authenticated;
revoke all on all tables in schema compliance from public,anon,authenticated;
revoke execute on all functions in schema compliance from public,anon,authenticated;
grant execute on function compliance.can(text) to authenticated;
DO $block$ declare r record; begin
 for r in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname in ('compliance_access','accept_policies','policy_status','request_privacy','export_my_data','admin_compliance_read','admin_compliance_setting','admin_privacy_review','admin_restrict_account','admin_staff_access') loop
 execute format('revoke all on function %s from public,anon,authenticated',r.sig);
 execute format('grant execute on function %s to authenticated',r.sig);
 end loop;
end $block$;

create function public.admin_kyc_reference(p_user uuid,p_reference text,p_status text,p_retain_until timestamptz,p_hold boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not compliance.can('kyc') or length(btrim(coalesce(p_reason,'')))<10 or length(btrim(coalesce(p_reference,'')))<4 or p_hold is null then raise exception 'KYC permission, provider reference and reason required'; end if;
 insert into compliance.kyc_records(user_id,provider_reference,review_status,retain_until,legal_hold) values(p_user,p_reference,p_status,p_retain_until,p_hold) on conflict(user_id) do update set provider_reference=excluded.provider_reference,review_status=excluded.review_status,retain_until=excluded.retain_until,legal_hold=excluded.legal_hold,updated_at=now();
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'kyc_review','account',p_user::text,jsonb_build_object('status',p_status,'reason',p_reason,'hold',p_hold));
end $$;
create function public.admin_retention_cleanup(p_reason text) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if not compliance.can('kyc') or not compliance.can('configuration') or length(btrim(coalesce(p_reason,'')))<20 then raise exception 'KYC and configuration permissions and reason required'; end if;
 if not exists(select 1 from compliance.settings where key='retention' and value->>'status'='confirmed') then raise exception 'Confirm retention schedule first'; end if;
 delete from compliance.kyc_records k where retain_until<now() and not legal_hold and not exists(select 1 from public.privacy_requests r where r.user_id=k.user_id and r.status in ('open','reviewing'));
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(auth.uid(),'kyc_retention_cleanup','kyc',jsonb_build_object('count',n,'reason',p_reason));return n;
end $$;
create function compliance.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new is distinct from old then insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'record_updated',TG_TABLE_NAME,to_jsonb(new)->>'id',jsonb_build_object('changed_fields',(select jsonb_agg(key) from jsonb_each(to_jsonb(new)) where value is distinct from to_jsonb(old)->key))); end if;return new;
end $$;
create trigger profile_change_audit after update on public.profiles for each row execute function compliance.audit_change();
create trigger payment_change_audit after update on public.purchases for each row execute function compliance.audit_change();
create trigger wallet_change_audit after update on public.wallets for each row execute function compliance.audit_change();
create trigger tipster_change_audit after update on public.tipsters for each row execute function compliance.audit_change();
revoke all on function public.admin_kyc_reference(uuid,text,text,timestamptz,boolean,text),public.admin_retention_cleanup(text),compliance.audit_change() from public,anon,authenticated;
grant execute on function public.admin_kyc_reference(uuid,text,text,timestamptz,boolean,text),public.admin_retention_cleanup(text) to authenticated;
-- A stale JWT cannot modify account information after restriction.
drop policy profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using(id=auth.uid() and status='active') with check(id=auth.uid() and status='active');
-- Optional simple bookmaker label; no bookmaker integration or affiliation is implied.
alter table public.predictions add column bookmaker text check(bookmaker in ('BetPawa','SportyBet','Betway','1xBet','Other'));
grant select(bookmaker) on public.predictions to anon,authenticated;
commit;
