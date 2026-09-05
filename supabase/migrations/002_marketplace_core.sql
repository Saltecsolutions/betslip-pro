-- Betslip Pro marketplace hardening and role workflows

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('admin','super_admin') and p.status = 'active'
  );
$$;

-- Automatically create role applications after signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  requested public.app_role;
  display_name text;
begin
  requested := coalesce((new.raw_user_meta_data->>'requested_role')::public.app_role, 'bettor');
  display_name := coalesce(new.raw_user_meta_data->>'full_name','User');

  insert into public.profiles (id, full_name, phone, role, requested_role, locale, age_verified)
  values (
    new.id,
    display_name,
    new.raw_user_meta_data->>'phone',
    case when requested in ('tipster','advertiser') then 'bettor'::public.app_role else requested end,
    requested,
    coalesce(new.raw_user_meta_data->>'locale','sw'),
    true
  );

  insert into public.wallets (user_id) values (new.id);

  if requested = 'tipster' then
    insert into public.tipsters (user_id, display_name, verification_status)
    values (new.id, display_name, 'pending');
  elsif requested = 'advertiser' then
    insert into public.advertisers (user_id, business_name, contact_name, status)
    values (new.id, display_name, display_name, 'pending');
  end if;

  return new;
end;
$$;

-- Tipster access policies.
drop policy if exists "tipster_read_own" on public.tipsters;
create policy "tipster_read_own" on public.tipsters for select
using (user_id = auth.uid() or verification_status = 'active' or public.is_admin());

drop policy if exists "tipster_update_own" on public.tipsters;
create policy "tipster_update_own" on public.tipsters for update
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "tipster_insert_predictions" on public.predictions;
create policy "tipster_insert_predictions" on public.predictions for insert
with check (
  exists (
    select 1 from public.tipsters t
    where t.id = tipster_id and t.user_id = auth.uid() and t.verification_status = 'active'
  )
);

drop policy if exists "tipster_read_own_predictions" on public.predictions;
create policy "tipster_read_own_predictions" on public.predictions for select
using (
  status in ('published','resulted')
  or exists (select 1 from public.tipsters t where t.id = tipster_id and t.user_id = auth.uid())
  or public.is_admin()
);

drop policy if exists "tipster_update_own_predictions" on public.predictions;
create policy "tipster_update_own_predictions" on public.predictions for update
using (exists (select 1 from public.tipsters t where t.id = tipster_id and t.user_id = auth.uid()))
with check (exists (select 1 from public.tipsters t where t.id = tipster_id and t.user_id = auth.uid()));

-- Admin access.
drop policy if exists "admin_profiles_all" on public.profiles;
create policy "admin_profiles_all" on public.profiles for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin_tipsters_all" on public.tipsters;
create policy "admin_tipsters_all" on public.tipsters for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin_predictions_all" on public.predictions;
create policy "admin_predictions_all" on public.predictions for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin_purchases_all" on public.purchases;
create policy "admin_purchases_all" on public.purchases for select using (public.is_admin());
drop policy if exists "admin_wallets_all" on public.wallets;
create policy "admin_wallets_all" on public.wallets for select using (public.is_admin());

-- A user may create only their own pending purchase. The 30/70 trigger calculates commissions.
drop policy if exists "purchases_insert_own" on public.purchases;
create policy "purchases_insert_own" on public.purchases for insert
with check (auth.uid() = user_id and payment_status = 'pending');

-- Securely return paid code only to buyer, owning tipster, or admin.
create or replace function public.get_betslip_code(p_prediction_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  code text;
begin
  select p.betslip_code into code
  from public.predictions p
  where p.id = p_prediction_id
    and (
      public.is_admin()
      or exists (
        select 1 from public.tipsters t
        where t.id = p.tipster_id and t.user_id = auth.uid()
      )
      or exists (
        select 1 from public.purchases pu
        where pu.prediction_id = p.id
          and pu.user_id = auth.uid()
          and pu.payment_status = 'paid'
      )
    );
  return code;
end;
$$;

grant execute on function public.get_betslip_code(uuid) to authenticated;

-- Admin approval promotes requested role.
create or replace function public.admin_set_tipster_status(p_tipster_id uuid, p_status public.account_status)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select user_id into uid from public.tipsters where id = p_tipster_id;
  update public.tipsters set verification_status = p_status where id = p_tipster_id;
  if p_status = 'active' then
    update public.profiles set role = 'tipster', status = 'active' where id = uid;
  elsif p_status in ('rejected','suspended') then
    update public.profiles set role = 'bettor' where id = uid;
  end if;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'tipster_status_changed','tipster',p_tipster_id::text,jsonb_build_object('status',p_status));
end;
$$;

grant execute on function public.admin_set_tipster_status(uuid, public.account_status) to authenticated;
