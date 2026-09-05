-- Production hardening. Run after both 002 migrations and 003.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare requested public.app_role; display_name text;
begin
  requested := case when new.raw_user_meta_data->>'requested_role' in ('tipster','advertiser') then (new.raw_user_meta_data->>'requested_role')::public.app_role else 'bettor'::public.app_role end;
  display_name := coalesce(nullif(new.raw_user_meta_data->>'full_name',''),'User');
  insert into public.profiles(id,full_name,phone,role,requested_role,locale,age_verified)
  values(new.id,display_name,new.raw_user_meta_data->>'phone','bettor',requested,
    case when new.raw_user_meta_data->>'locale'='en' then 'en' else 'sw' end,
    coalesce(new.raw_user_meta_data->>'age_confirmed','false')='true');
  insert into public.wallets(user_id) values(new.id);
  if requested='tipster' then
    insert into public.tipsters(user_id,display_name) values(new.id,display_name);
  elsif requested='advertiser' then
    insert into public.advertisers(user_id,business_name,contact_name) values(new.id,display_name,display_name);
  end if;
  return new;
end $$;

-- Owners can edit personal fields only; privileged state changes use guarded RPCs.
revoke update on public.profiles from anon,authenticated;
grant update(full_name,phone,locale) on public.profiles to authenticated;
revoke update on public.tipsters from anon,authenticated;
grant update(display_name,bio,sports_specialty,profile_image_url,location) on public.tipsters to authenticated;
alter table public.ledger_entries enable row level security;
alter table public.withdrawals enable row level security;
alter table public.audit_logs enable row level security;
create policy ledger_read on public.ledger_entries for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy audit_admin_read on public.audit_logs for select to authenticated using(public.is_admin());
create policy withdrawals_read on public.withdrawals for select to authenticated using(public.is_admin() or exists(select 1 from public.tipsters t where t.id=tipster_id and t.user_id=auth.uid()));
revoke insert,update,delete,truncate,references,trigger on public.wallets,public.ledger_entries,public.withdrawals,public.audit_logs,public.purchases from anon,authenticated;

-- Derive all purchase money and ownership from the published prediction.
create unique index purchases_buyer_prediction_unique on public.purchases(user_id,prediction_id);
create unique index purchase_verified_reference_unique on public.purchases(lower(btrim(payment_reference))) where payment_status='paid' and payment_reference is not null;
create or replace function public.create_purchase(p_prediction_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare p public.predictions; v_id uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and status='active' and age_verified) then raise exception 'Active adult account required'; end if;
  select * into p from public.predictions where id=p_prediction_id and status='published' and match_date>now() for share;
  if not found then raise exception 'Prediction unavailable'; end if;
  if exists(select 1 from public.tipsters where id=p.tipster_id and user_id=auth.uid()) then raise exception 'Cannot buy your own prediction'; end if;
  insert into public.purchases(user_id,prediction_id,tipster_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs)
  values(auth.uid(),p.id,p.tipster_id,p.price_tzs,0,0)
  on conflict(user_id,prediction_id) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.purchases where user_id=auth.uid() and prediction_id=p.id; end if;
  return v_id;
end $$;

-- Tipsters cannot self-publish, self-result, or change a sold prediction.
drop policy if exists tipster_insert_predictions on public.predictions;
create policy tipster_insert_predictions on public.predictions for insert to authenticated with check(
 status in ('draft','pending') and result='pending' and published_at is null and exists(
 select 1 from public.tipsters t join public.profiles pr on pr.id=t.user_id
 where t.id=tipster_id and t.user_id=auth.uid() and t.verification_status='active' and pr.status='active'));
drop policy if exists tipster_update_own_predictions on public.predictions;
-- Editing is disabled until a moderated revision workflow is available.

create or replace function public.submit_manual_payment(p_purchase_id uuid,p_reference text,p_note text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and status='active') then raise exception 'Active account required'; end if;
 if length(btrim(coalesce(p_reference,''))) not between 4 and 128 then raise exception 'Valid payment reference required'; end if;
 update public.purchases set payment_status='submitted',payment_reference=btrim(p_reference),payment_proof_note=left(p_note,2000),payment_submitted_at=now()
 where id=p_purchase_id and user_id=auth.uid() and payment_status='pending';
 if not found then raise exception 'Purchase cannot be submitted'; end if;
end $$;

-- Storage validates limits on the server, not only in the upload form.
update storage.buckets set file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'] where id='tipster-profiles';
drop policy tipster_profile_upload on storage.objects;
drop policy tipster_profile_update on storage.objects;
create policy tipster_profile_upload on storage.objects for insert to authenticated with check(bucket_id='tipster-profiles' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.tipsters t join public.profiles p on p.id=t.user_id where t.user_id=auth.uid() and p.status='active'));
create policy tipster_profile_update on storage.objects for update to authenticated using(bucket_id='tipster-profiles' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='tipster-profiles' and (storage.foldername(name))[1]=auth.uid()::text);

alter function public.calculate_purchase_split() set search_path='';
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.is_admin() to anon,authenticated;
grant execute on function public.create_purchase(uuid),public.get_betslip_code(uuid),public.get_prediction_protected_content(uuid),public.submit_manual_payment(uuid,text,text),public.admin_verify_manual_payment(uuid,integer),public.make_tipster_earnings_available(uuid,bigint),public.admin_set_tipster_status(uuid,public.account_status) to authenticated;
