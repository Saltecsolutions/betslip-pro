alter type public.payment_status add value if not exists 'submitted';

alter table public.tipsters
  add column if not exists profile_image_url text,
  add column if not exists location text,
  add column if not exists trust_note text;

alter table public.purchases
  add column if not exists payment_method text not null default 'selcom_lipa_namba',
  add column if not exists payment_submitted_at timestamptz,
  add column if not exists payment_verified_at timestamptz,
  add column if not exists verified_by uuid references public.profiles(id),
  add column if not exists payment_proof_note text;

create or replace function public.submit_manual_payment(
  p_purchase_id uuid,
  p_reference text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.purchases
  set payment_status = 'submitted',
      payment_reference = p_reference,
      payment_proof_note = p_note,
      payment_submitted_at = now()
  where id = p_purchase_id
    and user_id = auth.uid()
    and payment_status = 'pending';

  if not found then
    raise exception 'Purchase not found or cannot be submitted';
  end if;
end;
$$;

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
  select role in ('admin','super_admin') into v_is_admin
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
  select role in ('admin','super_admin') into v_is_admin from public.profiles where id = auth.uid();
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

create policy "tipster_update_own_profile" on public.tipsters
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

insert into storage.buckets (id,name,public)
values ('tipster-profiles','tipster-profiles',true)
on conflict (id) do nothing;

create policy "tipster_profile_upload" on storage.objects
for insert to authenticated
with check (bucket_id='tipster-profiles' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "tipster_profile_update" on storage.objects
for update to authenticated
using (bucket_id='tipster-profiles' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "tipster_profile_public_read" on storage.objects
for select using (bucket_id='tipster-profiles');
