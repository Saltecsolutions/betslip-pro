create extension if not exists pgcrypto;

create type public.app_role as enum ('bettor','tipster','advertiser','admin','super_admin');
create type public.account_status as enum ('pending','active','suspended','rejected');
create type public.prediction_status as enum ('draft','pending','published','resulted','rejected','removed');
create type public.prediction_result as enum ('pending','won','lost','void');
create type public.payment_status as enum ('pending','paid','failed','refunded');
create type public.withdrawal_status as enum ('pending','approved','rejected','paid');
create type public.campaign_status as enum ('draft','pending','approved','active','paused','completed','rejected');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.app_role not null default 'bettor',
  requested_role public.app_role,
  locale text not null default 'sw' check (locale in ('sw','en')),
  age_verified boolean not null default false,
  status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tipsters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique not null references public.profiles(id) on delete cascade,
  display_name text not null,
  bio text,
  sports_specialty text[],
  verification_status public.account_status not null default 'pending',
  rating numeric(3,2) not null default 0,
  win_rate numeric(5,2) not null default 0,
  roi_30d numeric(8,2) not null default 0,
  avg_odds numeric(6,2) not null default 0,
  verified_picks integer not null default 0,
  total_sales integer not null default 0,
  total_followers integer not null default 0,
  betslip_pro_score numeric(5,2) not null default 0,
  created_at timestamptz not null default now()
);

create table public.predictions (
  id uuid primary key default gen_random_uuid(),
  tipster_id uuid not null references public.tipsters(id) on delete cascade,
  title text not null,
  sport text not null,
  league text,
  match_name text not null,
  prediction_text text not null,
  betslip_code text,
  odds numeric(8,2),
  confidence_level integer check (confidence_level between 1 and 100),
  price_tzs integer not null default 0 check (price_tzs >= 0),
  category text,
  risk_level text check (risk_level in ('low','medium','high')),
  match_date timestamptz not null,
  status public.prediction_status not null default 'draft',
  result public.prediction_result not null default 'pending',
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  prediction_id uuid not null references public.predictions(id),
  tipster_id uuid not null references public.tipsters(id),
  amount_tzs integer not null check (amount_tzs >= 0),
  platform_commission_tzs integer not null,
  tipster_commission_tzs integer not null,
  processing_fee_tzs integer not null default 0,
  payment_status public.payment_status not null default 'pending',
  payment_reference text,
  created_at timestamptz not null default now(),
  constraint commission_split_check check (platform_commission_tzs + tipster_commission_tzs = amount_tzs)
);

create table public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  available_balance_tzs bigint not null default 0,
  pending_balance_tzs bigint not null default 0,
  total_withdrawn_tzs bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid references public.purchases(id),
  user_id uuid references public.profiles(id),
  entry_type text not null,
  amount_tzs bigint not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  tipster_id uuid not null references public.tipsters(id),
  amount_tzs integer not null check (amount_tzs > 0),
  payment_method text not null,
  account_number text not null,
  status public.withdrawal_status not null default 'pending',
  admin_note text,
  created_at timestamptz not null default now()
);

create table public.advertisers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique not null references public.profiles(id) on delete cascade,
  business_name text not null,
  contact_name text,
  status public.account_status not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.ad_campaigns (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.advertisers(id) on delete cascade,
  name text not null,
  package text check (package in ('starter','growth','premium')),
  placement text[] not null default '{}',
  budget_tzs bigint not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  target_config jsonb not null default '{}'::jsonb,
  creative_sw jsonb,
  creative_en jsonb,
  status public.campaign_status not null default 'draft',
  impressions bigint not null default 0,
  clicks bigint not null default 0,
  spend_tzs bigint not null default 0,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  requested public.app_role;
begin
  requested := coalesce((new.raw_user_meta_data->>'requested_role')::public.app_role, 'bettor');
  insert into public.profiles (id, full_name, phone, role, requested_role, locale, age_verified)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name','User'),
    new.raw_user_meta_data->>'phone',
    case when requested in ('tipster','advertiser') then 'bettor'::public.app_role else requested end,
    requested,
    coalesce(new.raw_user_meta_data->>'locale','sw'),
    true
  );
  insert into public.wallets (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.calculate_purchase_split()
returns trigger
language plpgsql
as $$
begin
  new.platform_commission_tzs := round(new.amount_tzs * 0.30);
  new.tipster_commission_tzs := new.amount_tzs - new.platform_commission_tzs;
  return new;
end;
$$;

create trigger purchases_calculate_split
before insert or update of amount_tzs on public.purchases
for each row execute procedure public.calculate_purchase_split();

alter table public.profiles enable row level security;
alter table public.tipsters enable row level security;
alter table public.predictions enable row level security;
alter table public.purchases enable row level security;
alter table public.wallets enable row level security;
alter table public.advertisers enable row level security;
alter table public.ad_campaigns enable row level security;

create policy "profiles_read_own" on public.profiles for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id);
create policy "public_tipsters_read" on public.tipsters for select using (verification_status = 'active');
create policy "published_predictions_read" on public.predictions for select using (status in ('published','resulted'));
create policy "purchases_read_own" on public.purchases for select using (auth.uid() = user_id);
create policy "wallet_read_own" on public.wallets for select using (auth.uid() = user_id);
create policy "advertiser_read_own" on public.advertisers for select using (auth.uid() = user_id);
create policy "campaigns_read_own" on public.ad_campaigns for select using (
  exists (select 1 from public.advertisers a where a.id = advertiser_id and a.user_id = auth.uid())
);
