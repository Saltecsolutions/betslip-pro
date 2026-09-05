# Betslip Pro

Betslip Pro is a bilingual (Kiswahili/English) sports prediction marketplace for Tanzania. It connects bettors/users with verified tipsters and supports a separate advertiser marketplace. Betslip Pro is not a bookmaker and does not place bets for users.

## V1 business rules

- Roles: bettor, tipster, advertiser, admin, super_admin.
- Tipsters must be approved before publishing paid predictions.
- Paid betslip codes stay locked until a successful purchase is verified.
- Marketplace split: 60% Betslip Pro / 40% tipster.
- Payment-processing fees are recorded separately and do not change the 60/40 marketplace split.
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
- Automatic 60/40 marketplace commission calculation at database level.
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

## Premium V1 redesign — September 5, 2026

The Next.js/Supabase architecture and Selcom manual-verification flow are preserved.
The application now has a shared midnight-navy/lime design system, stadium artwork,
EN/SW language preference, mobile navigation, secure prediction previews, tipster
rankings and public records, account/earnings screens, activity, buyer protection,
and admin moderation/payment/integrity workspaces.

Apply the two new migrations after the existing migrations. They have already been
applied to the connected Betslip Pro Supabase project; do not replay them there:
- `20260905121759_premium_v1.sql`
- `20260905122045_settlement_and_purchase_hardening.sql`

The direct public grant on `predictions.match_name` is intentionally removed.
Teams, picks and codes are available only from the guarded purchased-content RPC.
Older frontend releases that explicitly select `match_name` must be upgraded to
this version together with these migrations. Published records cannot be deleted,
changed or hidden; results require an append-only settlement event. Tipster
suspension blocks new purchases. A refund removes future paid-content access and
reverses the recorded tipster liability after the manual transfer is reconciled.

### Performance definitions

ROI and profit use one unit per prediction, not customer stake or sales revenue.
Won predictions return settled odds minus one; losses return minus one; voids
and pending results are excluded. Rankings for ROI, profit and consistency require
20 settled wins/losses. Consistency uses the Wilson lower confidence bound.
Trending uses paid sales in the past 30 days then followers. New & Rising covers
90-day members ordered by settled sample size. Identity verification is distinct
from prediction success. Empty records display no invented statistics.

### Results integration

`POST /api/settlement` accepts `{selection_id, result, reference}` from a trusted
provider adapter with `Authorization: Bearer BETSLIP_SETTLEMENT_SECRET`.
It requires server-only `SUPABASE_SERVICE_ROLE_KEY` and `BETSLIP_SETTLEMENT_SECRET`.
The route returns 503 until configured. No provider subscription or credentials
are present, so no live sports feed is active.

An operator must map each private `prediction_selections` row to a provider event,
market and selection before publication. Service-only ingestion records terminal
results and settles only when the full declared set is complete. Replay is
idempotent. Mapped mixed won/void accumulators use the remaining winning-leg odds; unsupported mappings remain in review. Unsupported/unmapped predictions remain pending. Admin-reviewed
settlements require a public evidence reference and are permanently attributed.

Notifications are in-app: followed-expert publication, settlement, dispute decisions,
and available payouts. Email/push and timed kickoff notifications are not connected.
Selcom verification, refund transfers and payout transfers remain manual; approving
an application or request does not send money. Production SMTP and final Auth
redirect allowlists from the existing launch checklist still need operator setup.

### Verification

`npm run build` checks compilation and TypeScript and renders all static routes.
`supabase/tests/premium_v1.sql` tests grants, buyer isolation, 60/40, idempotency,
immutable records, follow/notification access and refund reversal.
`supabase/tests/settlement_v1.sql` tests Won/Lost/Void aggregation, replays and ROI.
Tests were executed against the connected database inside rolled-back transactions.
The security advisor reported no missing-RLS tables; its remaining warnings flag
intentional public aggregates and guarded SECURITY DEFINER RPCs. The public
aggregate contains no buyer identities or protected selections.

No browser interaction/visual test was run in this task. Responsive breakpoints,
keyboard focus, accessible labels and reduced-motion styles were reviewed in source.
The source is Next.js server output; a Cloudflare Worker adapter is required to
publish this unchanged architecture through Sites. The standard Node/Vercel build
remains supported. No public deployment or domain change was performed.

## Focused V1 completion — 5 September 2026

The current mobile home order is greeting/search → upcoming published games → featured slip → Top Verified → Trending Predictions → Explore Marketplace. Mobile navigation is Home, Explore, Betslips, Activity, Profile. The existing stadium artwork and sports design system are preserved.

`20260905123311_focused_v1_completion.sql` adds server-assigned publication timestamps, append-only settlement/audit evidence, locked selection mappings, public analysis and optional self-reported confidence, purchase-backed ratings, compliance reviews, and aggregate discovery/profile/business RPCs. Applied to the existing Betslip Pro Supabase project. Published legacy picks are not rewritten.

Performance windows are 7D/30D/90D/All Time by settlement timestamp. One unit per won/lost slip; voids are shown in settled totals but excluded from ROI/win-rate denominators. Effective settlement odds handle partial void adjustments without rewriting published odds. Average odds are the original published odds of decided picks. Recent form is newest first. Levels and thresholds are visible in the profile; identity verification is separate from a performance level.

Business conversion means paid orders / created non-refunded orders, not visitor conversion. Ratings are immutable, one per paid purchase, and refunded purchases are excluded from aggregate ratings. Revenue continues to use the fixed 40% tipster / 60% platform split; processing fees remain a separate ledger entry and total.

Integrity flags cover unusually high win rate/ROI, near-kickoff publication, buyer disputes and overdue settlements. Flags request human review and do not themselves prove fraud. Compliance holds remove discovery eligibility/earned levels; account suspension remains the separate control to stop selling. The historic record stays visible.

Validation: production build and TypeScript checks pass. Transactional hosted SQL suites `premium_v1.sql`, `settlement_v1.sql`, `focused_v1.sql`, and `levels_v1.sql` pass. Fixtures are rolled back; zero test users remain. Do not run fixture suites as user traffic: tests temporarily lock tables for historical fixtures. Browser QA covered desktop, 390px and 320px mobile, English/Kiswahili, populated card/metric fixtures, period controls and overflow. The temporary QA page is not shipped.

Operational limits: frontend deployment is still required; live scores and a trusted results-provider adapter are not configured. Unmapped results remain pending for evidence-based admin settlement. Selcom verification/payout operations remain the existing manual workflow; no live payment was charged in QA. Browser verification of authenticated buyer/admin journeys was limited to auth gates, while their data/authorization paths were verified transactionally in SQL.

## Compliance, privacy and authentication update

See [COMPLIANCE-OPERATIONS.md](docs/COMPLIANCE-OPERATIONS.md) for current delivered functionality, migrations, staff permissions, policy lifecycle, deletion/retention procedures, Google/Apple credentials and callback configuration, verification and launch dependencies. This section supersedes earlier general-admin access and identity-verification descriptions. Frontend deployment is still required.

## V1 automatic pricing and finance completion

See [AI pricing, economics, validation and rollout](docs/AI-PRICING-V1.md). Tipsters no longer enter prices. The studio, exception queues, tipster wallets and partner/admin revenue views use server-enforced rules. The migration and app are live as of 5 September 2026; see the linked production verification notes for remaining account acceptance and results-provider setup. Run `npm run test:db`, `npm test`, `npm run build` and `npm run typecheck` before release.
