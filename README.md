# Betslip Pro

Betslip Pro is a bilingual (Kiswahili/English) sports prediction marketplace for Tanzania. It connects bettors/users with verified tipsters and supports a separate advertiser marketplace. Betslip Pro is not a bookmaker and does not place bets for users.

## V1 business rules

- Roles: bettor, tipster, advertiser, admin, super_admin.
- Tipsters must be approved before publishing paid predictions.
- Paid betslip codes stay locked until a successful purchase is verified.
- Marketplace split: 30% Betslip Pro / 70% tipster.
- Payment-processing fees are recorded separately and do not change the 30/70 marketplace split.
- Sponsored placements must be clearly labelled and never alter verified tipster performance metrics or organic rankings.
- User-facing product supports Kiswahili and English.
- 18+ and responsible prediction/gambling disclaimers are mandatory.

## Stack

- Next.js + TypeScript
- Supabase Auth + PostgreSQL
- Vercel-ready frontend
- Selcom-ready payment architecture (live payment integration pending credentials)

## Setup

1. Copy `.env.example` to `.env.local`.
2. Create a Supabase project.
3. Run `supabase/schema.sql` in the Supabase SQL editor.
4. Add Supabase URL and anon key to `.env.local`.
5. Install dependencies with `npm install`.
6. Run `npm run dev`.

## Current implementation

- Premium sports-tech landing page.
- SW/EN translation foundation.
- Real Supabase registration flow for bettor, tipster and advertiser requests.
- Database schema for profiles, tipsters, predictions, purchases, wallets, withdrawals, ledger, advertisers, campaigns and audit logs.
- Automatic 30/70 marketplace commission calculation at database level.
- Row-level security foundation.
- Advertise on Betslip Pro page and Starter/Growth/Premium package structure.

## Next implementation block

- Login/logout/password reset and auth middleware.
- Role-based dashboards and route guards.
- Tipster application/approval workflow.
- Create/manage predictions and secure paid-code unlock endpoint.
- Purchase/payment state machine and Selcom adapter.
- Wallet/withdrawal workflow.
- Rankings, reviews and verified performance calculations.
- Advertiser campaign dashboard and admin approval.
- Admin/super-admin dashboard and bootstrap flow.

## Production deployment (September 2026)

Supabase project: `iqdgtnwgphqstpazquku` (Betslip Pro, ap-south-1).
Apply SQL in this explicit order (the two legacy 002 files share a prefix):

1. `supabase/schema.sql`
2. `supabase/migrations/002_marketplace_core.sql`
3. `supabase/migrations/002_manual_selcom_and_tipster_profiles.sql`
4. `supabase/migrations/003_paid_content_protection.sql`
5. `supabase/migrations/004_launch_security.sql`
6. `supabase/migrations/005_admin_and_advertiser.sql`

The hosted project already has these migrations applied. Do not replay the schema.
`supabase/tests/launch_security.sql` validates the payment/security flow within a rolled-back transaction.

Set the public Supabase URL and publishable key in the hosting environment. Keep
`NEXT_PUBLIC_SELCOM_LIPA_NUMBER=70062404` and
`NEXT_PUBLIC_SELCOM_MERCHANT_NAME=SALTEC SOLUTIONS`.
Set `NEXT_PUBLIC_APP_URL` to the final HTTPS origin and configure Supabase Auth Site URL
and the exact `/auth/callback` redirect accordingly. Email confirmation must remain enabled.
Configure production SMTP before opening registration to customers.

Super Admin: register and verify the owner's email first. A trusted database operator can
call `public.bootstrap_super_admin(user_id)` once. It checks email confirmation and serializes
concurrent attempts. The optional HTTP bootstrap route needs server-only
`SUPABASE_SERVICE_ROLE_KEY` and a random `BETSLIP_PRO_BOOTSTRAP_ADMIN_SECRET`; it accepts only
an existing confirmed user ID, never a password. Leave these environment variables unset
when bootstrapping through the database, so the HTTP route stays disabled.

Tipster earnings stay pending after admin verification; processing fees are separate.
Payout execution remains manual and must be reconciled by the operator; no payout provider
or automatic money transfer is configured. Advertiser applications require admin approval;
the portal accepts campaigns for review but does not automatically serve or charge for ads.
