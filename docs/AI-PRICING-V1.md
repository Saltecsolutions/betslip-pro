# V1 automatic pricing and operations

The current work branch implements server-controlled pricing, automated submission validation, exception review, payout reservations and a complete revenue summary. It is prepared for rollout; the new migration has not been applied to production.

## Price decisions

`my_ai_price` displays the current price and a reason in English/Kiswahili. `submit_prediction` accepts content, never a price. Database triggers assign the engine price again at publication. Direct client inserts/updates are revoked, including column grants. Existing published content, historical prices and purchase amounts stay fixed.

The V1 AI price model is a versioned, deterministic multi-signal scoring model (`v1.0`), not a generative model or an externally trained predictor. Every review stores the input snapshot, old/new price, model version, bilingual reason and timestamp in append-only `engine.price_reviews`. There is no external AI API dependency.

Bands: **1,000 → 1,500 → 2,000 → 3,000 → 5,000 → 7,500 → 10,000 TZS**. New tipsters start at TZS 1,000. Each review moves at most one band in either direction.

Both conditions must hold: **five additional evidenced Won/Lost results AND 24 hours since the last review**. Voids do not advance the counter. Settlement triggers, the next studio/submission request and a daily 00:15 UTC database job evaluate eligibility; these do not bypass either condition.

Only published, resulted predictions joined to matching immutable settlement evidence count. Unit ROI uses effective settled odds, excluding voids. Pricing caps each result's odds at 100 to limit outlier influence; public performance statistics retain their existing definitions. Recent form uses the latest 20 decisions. Marketplace signals use the last 90 days.

| Signal | Maximum positive score |
|---|---:|
| Unit ROI (clamped to 0–100%) | 20 |
| Verified win rate | 15 |
| Last-20 win rate | 15 |
| Mean capped odds, normalized to 5 | 5 |
| Consistency, 1 / (1 + return standard deviation) | 10 |
| Share of paid buyers with repeat purchases | 10 |
| Share of published slips with a paid order | 5 |
| Paid / non-refunded created orders | 5 |
| Paid-purchase ratings, at least 5 ratings | 10 |
| Sample size, normalized to 200 | 5 |

Subtract 50 × (dispute rate + refund rate). Score thresholds 35/45/55/65/75/85 select the ascending paid bands. Additional caps: fewer than 20 decisions remain at 1,000; fewer than 40/75/150/200 decisions cap prices at 2,000/3,000/5,000/7,500. Fewer than 5 paid orders cap at 1,000; fewer than 20 paid orders cap at 2,000. An integrity hold, nonpositive overall or recent ROI, or refund/dispute rate above 10% targets the floor, still subject to the one-step decrease rule. These are launch policy choices, not statistically calibrated promises of value.

“Demand” is checkout completion, not visitor conversion. Disputes count distinct purchases with open, approved or refunded cases; rejected reports do not penalize pricing. Ratings count only paid orders. No claims about visitors or scarcity are inferred.

## Publication and settlement

The first **five reviewer-approved publications** require review. After that, active sellers with accepted agreements, verified KYC and no risk flags can auto-publish. Server checks cover required/bounded fields, future kickoff, odds, selection count, bookmaker, duplicate slips and rapid repeated submission. Near kickoff, unusually large slips/odds, integrity holds and unusual performance route to review. These checks validate the submission structure and available signals; they do not establish that narrative predictions are true.

The bilingual studio supports optional structured selections with provider event/market references. A supplied mapping must cover every selection and match total odds. Duplicate exact selections fail; correlated selections require review. Selections freeze at publication. Without usable mappings, settlement remains manual.

Signed provider callbacks serialize on the parent betslip and reject conflicting corrections. Complete Won/Lost/Void sets settle automatically. Mixed Won/Void accumulators multiply only winning-leg odds; all voids settle at effective odds 1. Unmapped/incomplete sets remain pending. Provider credentials and an adapter matching the selected data supplier are still required before live automatic settlement can run.

Needs Review exposes validation reasons and retains snapshot revision checks. Reported shows aggregated buyer reports without buyer/payment details. Suspicious Activity includes flagged submissions and overdue results. Existing admin trust operations handle investigation, holds, refunds and manual evidence-backed settlement. Expired pending slips may be rejected, but cannot be published.

## Economics and wallets

Orders snapshot the 70% tipster / 30% platform split. Default WHT allocation is **5 percentage points of gross**, inside the platform share, leaving 25% before processing costs. This implements the agreed allocation and is not confirmation of a statutory tax treatment or remittance. `configure_wht_allocation` requires finance plus configuration permission, validates 0–3,000 basis points, and audits changes. Historical snapshots never change.

Revenue totals aggregate the full purchase history, excluding unpaid submissions and refunded sales. Submitted amounts, refunds, processing fees and completed tipster payouts are separate. Refunds reverse the original platform/WHT allocations; processing costs remain expenses. Ledger allocation rows are subdivisions of the gross platform commission and must not be added to it again.

Finance staff can release reconciled pending earnings, with an audit and ledger record. Tipsters can request withdrawals from available funds. The amount is reserved atomically; a request key makes retries idempotent. Finance staff record the actual transfer reference or reject and restore reserved funds. Repeat processing and duplicate transfer references fail. The application records transfers; it does not initiate bank/mobile-money payouts.

Pre-existing withdrawals have `funds_reserved=false` and require reconciliation before using the new finalization path. This prevents treating an old unreserved request as already funded.

Jimmy's verified `jdaking08@gmail.com` account can read `/revenue`, also linked from My Account. This permission exposes only aggregate revenue, not purchase references, bank details, payout actions, KYC or configuration. Finance/admin access remains separately scoped. The platform net is not an assumed personal dividend payable to Jimmy.

## Rollout and verification

1. Review and apply only `20260905155722_ai_pricing_and_v1_operations.sql` to the current database after all existing migrations. Historical local filenames differ from some hosted migration IDs; do not blindly replay the whole migration directory against production.
2. Deploy this branch's app with the existing public Supabase configuration. Apply the migration before switching the UI because client prediction inserts are replaced by an RPC.
3. Confirm the `betslip-ai-pricing` cron job exists. The isolated test runner stubs Supabase scheduling, storage scaffolding and outbound service integrations; it does not validate hosted scheduling or provider delivery.
4. Reconcile any legacy pending/approved withdrawals, then verify owner/finance/partner access with real accounts. Confirm Jimmy's verified email and accepted policies.
5. Configure the trusted results adapter and settlement secret to enable live callbacks. Otherwise use the existing evidence-backed admin settlement queue.

Local checks: `npm run test:db`, `npm test`, `npm run build`, `npm run typecheck`. The database runner starts isolated PostgreSQL (PGlite), loads the complete schema/migration chain, runs SQL scenarios and rolls them back. No test users, payments, messages or results are written to production. It covers pricing cadence and band/risk caps, forged-price rejection, immutable publications, probation/auto-publication, mapped partial-void settlement, callback replay, refund accounting, payout reservations/retries, partner scope, RLS and legacy business flows. Multi-session load testing and real authenticated browser/provider tests are not claimed.

The live security advisor was inspected. Existing callable SECURITY DEFINER functions are still flagged; their checks remain tested, while new public RPCs use invoker wrappers around guarded private implementations. Private tables intentionally have RLS with no direct client policies. Leaked-password protection is an existing configuration warning. See [function security guidance](https://supabase.com/docs/guides/database/functions) and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
