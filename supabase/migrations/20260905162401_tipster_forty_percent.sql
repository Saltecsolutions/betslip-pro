-- New orders: tipster 40%, platform 60%. Existing order snapshots stay immutable.
-- Round the platform share to whole TZS; tipster receives the exact remainder.
create or replace function public.calculate_purchase_split()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  new.platform_commission_tzs := round(new.amount_tzs * 0.60);
  new.tipster_commission_tzs := new.amount_tzs - new.platform_commission_tzs;
  return new;
end;
$$;

create or replace function engine.allocate_sale() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
 select wht_bps into new.wht_bps from engine.economics where singleton;
 new.platform_commission_tzs:=round(new.amount_tzs*0.60);
 new.tipster_commission_tzs:=new.amount_tzs-new.platform_commission_tzs;
 new.wht_allocation_tzs:=round(new.amount_tzs*new.wht_bps/10000.0);
 new.platform_net_tzs:=new.platform_commission_tzs-new.wht_allocation_tzs;
 elsif (new.amount_tzs,new.tipster_id,new.user_id,new.prediction_id,new.wht_bps,new.wht_allocation_tzs,new.platform_net_tzs,new.platform_commission_tzs,new.tipster_commission_tzs)
 is distinct from (old.amount_tzs,old.tipster_id,old.user_id,old.prediction_id,old.wht_bps,old.wht_allocation_tzs,old.platform_net_tzs,old.platform_commission_tzs,old.tipster_commission_tzs) then raise exception 'Order economics and ownership are immutable';end if;
 return new;
end $$;

-- Require explicit acceptance of the revised seller agreement; keep base policy acceptances valid.
create or replace function compliance.accept_policies(p_version text,p_locale text,p_seller boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and (email_confirmed_at is not null or phone_confirmed_at is not null)) then raise exception 'Verified sign-in required'; end if;
 if (p_version is null or p_version not in ('2026-09-05','2026-09-05-v2') or (p_seller and p_version <> '2026-09-05-v2')) or p_locale not in ('en','sw') or p_locale is null or p_seller is null then raise exception 'Reload current policies'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'Active account required'; end if;
 insert into public.policy_acceptances(user_id,document,version,locale) select auth.uid(),d,case when d='seller' then '2026-09-05-v2' else '2026-09-05' end,p_locale from unnest(case when p_seller then array['terms','privacy','adult','seller'] else array['terms','privacy','adult'] end) d on conflict do nothing;
 update public.profiles set age_verified=true where id=auth.uid();
 if p_seller then
 insert into public.tipsters(user_id,display_name) values(auth.uid(),'New tipster') on conflict(user_id) do nothing;
 update public.profiles set requested_role='tipster' where id=auth.uid() and role='bettor';
 end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'policies_accepted','account',auth.uid()::text,jsonb_build_object('version',p_version,'seller',p_seller));
end $$;
create or replace function compliance.accepted(p_user uuid,p_seller boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=p_user and status='active') and (select count(*) from public.policy_acceptances where user_id=p_user and version=case when document='seller' then '2026-09-05-v2' else '2026-09-05' end and document=any(case when p_seller then array['terms','privacy','adult','seller'] else array['terms','privacy','adult'] end))=case when p_seller then 4 else 3 end;
$$;
create or replace function compliance.policy_status() returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_build_object('accepted',coalesce(compliance.accepted(auth.uid()),false),'seller',coalesce(compliance.accepted(auth.uid(),true),false),'version','2026-09-05-v2'); $$;
