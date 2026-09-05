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
