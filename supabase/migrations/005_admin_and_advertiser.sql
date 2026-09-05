create or replace function public.admin_verify_manual_payment(
  p_purchase_id uuid,
  p_processing_fee_tzs integer default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_tipster_user uuid;
  v_tipster_amount integer;
begin
  select role in ('admin','super_admin') and status='active' into v_is_admin
  from public.profiles where id = auth.uid();
  if coalesce(v_is_admin,false) = false then raise exception 'Admin only'; end if;

  select t.user_id, p.tipster_commission_tzs
    into v_tipster_user, v_tipster_amount
  from public.purchases p
  join public.tipsters t on t.id = p.tipster_id
  where p.id = p_purchase_id
    and p.payment_status = 'submitted'
  for update;

  if v_tipster_user is null then raise exception 'Purchase not found or not submitted'; end if;

  update public.purchases
  set payment_status = 'paid',
      processing_fee_tzs = greatest(p_processing_fee_tzs,0),
      payment_verified_at = now(),
      verified_by = auth.uid()
  where id = p_purchase_id;

  update public.wallets
  set pending_balance_tzs = pending_balance_tzs + v_tipster_amount,
      updated_at = now()
  where user_id = v_tipster_user;

  insert into public.ledger_entries(purchase_id,user_id,entry_type,amount_tzs,metadata)
  values
    (p_purchase_id,v_tipster_user,'tipster_pending_earning',v_tipster_amount,'{"status":"pending"}'::jsonb),
    (p_purchase_id,null,'platform_commission',(select platform_commission_tzs from public.purchases where id=p_purchase_id),'{}'::jsonb),
    (p_purchase_id,null,'payment_processing_fee',greatest(p_processing_fee_tzs,0),'{}'::jsonb);
end;
$$;

create or replace function public.make_tipster_earnings_available(p_tipster_user_id uuid, p_amount_tzs bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_is_admin boolean;
begin
  select role in ('admin','super_admin') and status='active' into v_is_admin from public.profiles where id = auth.uid();
  if coalesce(v_is_admin,false) = false then raise exception 'Admin only'; end if;
  if p_amount_tzs <= 0 then raise exception 'Amount must be positive'; end if;

  update public.wallets
  set pending_balance_tzs = pending_balance_tzs - p_amount_tzs,
      available_balance_tzs = available_balance_tzs + p_amount_tzs,
      updated_at = now()
  where user_id = p_tipster_user_id
    and pending_balance_tzs >= p_amount_tzs;

  if not found then raise exception 'Insufficient pending balance'; end if;
end;
$$;


create or replace function public.bootstrap_super_admin(p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(74639201);
 if exists(select 1 from public.profiles where role='super_admin') then raise exception 'Bootstrap already completed'; end if;
 if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then raise exception 'Confirmed user required'; end if;
 update public.profiles set role='super_admin',requested_role='super_admin',status='active' where id=p_user_id;
 if not found then raise exception 'Profile missing'; end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id) values(p_user_id,'super_admin_bootstrapped','profile',p_user_id::text);
end $$;
revoke all on function public.bootstrap_super_admin(uuid) from public,anon,authenticated;
grant execute on function public.bootstrap_super_admin(uuid) to service_role;

create policy admin_advertisers_read on public.advertisers for select to authenticated using(public.is_admin());
create policy admin_campaigns_read on public.ad_campaigns for select to authenticated using(public.is_admin());
create or replace function public.admin_set_advertiser_status(p_advertiser_id uuid,p_status public.account_status)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 update public.advertisers set status=p_status where id=p_advertiser_id returning user_id into v_uid;
 if v_uid is null then raise exception 'Advertiser not found'; end if;
 update public.profiles set role=case when p_status='active' then 'advertiser'::public.app_role else 'bettor'::public.app_role end where id=v_uid and role in ('bettor','advertiser');
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'advertiser_status_changed','advertiser',p_advertiser_id::text,jsonb_build_object('status',p_status));
end $$;
create or replace function public.submit_ad_campaign(p_name text,p_package text,p_budget_tzs bigint)
returns uuid language plpgsql security definer set search_path='' as $$
declare a_id uuid; c_id uuid;
begin
 select a.id into a_id from public.advertisers a join public.profiles p on p.id=a.user_id where a.user_id=auth.uid() and a.status='active' and p.status='active';
 if a_id is null then raise exception 'Approved advertiser required'; end if;
 if length(btrim(p_name)) not between 1 and 120 or p_package not in ('starter','growth','premium') or p_budget_tzs<=0 then raise exception 'Valid campaign name, package and budget required'; end if;
 insert into public.ad_campaigns(advertiser_id,name,package,budget_tzs,status) values(a_id,btrim(p_name),p_package,p_budget_tzs,'pending') returning id into c_id;
 return c_id;
end $$;
revoke all on function public.admin_set_advertiser_status(uuid,public.account_status), public.submit_ad_campaign(text,text,bigint) from public,anon;
grant execute on function public.admin_set_advertiser_status(uuid,public.account_status), public.submit_ad_campaign(text,text,bigint) to authenticated;
