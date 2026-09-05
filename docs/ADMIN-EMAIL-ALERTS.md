# Important admin email alerts

Recipient: salmin@saltecsolutions.co.tz. Sender: Betslip Pro <noreply@betslip.co.tz>.

Database triggers queue new partnership and privacy requests, purchase disputes, payments transitioning to failed, staff permission/role changes and tipster integrity reviews. Routine signups, logins and sales do not email the owner. Payment alerts report the stored status; no payment provider reconciliation is implied. No historic events are backfilled.

An Edge Function named `admin-alerts` checks the private queue every two minutes through pg_cron/pg_net. Add **RESEND_API_KEY** in Supabase → Edge Functions → Secrets. Use the existing Betslip Pro sending key scoped to betslip.co.tz. This is separate from the key saved in Auth SMTP. Never add it as a NEXT_PUBLIC environment variable, commit it, or paste it in chat. Supabase supplies SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to the function automatically.

The scheduler's random authentication token is generated in Vault as `betslip_admin_alerts_worker`; no manual token copy is required. Gateway JWT verification is intentionally disabled ONLY for this function: its handler requires a 64-character bearer token, and the service-role-only claim RPC validates that token against Vault before any queue access. Anonymous and authenticated clients cannot call worker RPCs or read outbox tables. Keep the admin_alerts schema unexposed in the Data API.

`/admin/alerts` is restricted by database checks to active superadmins. It supports refresh, pause/resume and one test per ten minutes. Reads and setting changes are audited. Paused events remain queued. Missing Resend credentials do not consume attempts. Worker health is updated even without credentials. First sending test is required after setting the key; verify the Resend email event and recipient inbox separately.

The queue uses transactionally claimed batches of five with five-minute leases, stale-lease protection and up to six attempts with exponential backoff. Resend idempotency key is stable per event. Retries stop twenty hours after the first attempt to stay within Resend's documented 24-hour deduplication window. Errors store sanitized codes only. An accepted status means Resend accepted the API request, not that the email reached the inbox. Delivery/bounce status remains in Resend; webhook reconciliation is not yet implemented. Failed rows require investigation; automatic unlimited retries or unsafe replay are deliberately unavailable.

Email bodies contain static bilingual event labels, a dashboard link and a queue reference only. They contain no request details, identity information, KYC, payment references or free-form user content. Private outbox records retain only routing and delivery metadata. No statutory retention period is asserted; do not delete audit evidence as part of mail cleanup. Pending/failed events should remain available for incident review until an approved internal retention schedule covers them.

Verification: `node --test supabase/functions/admin-alerts/handler.test.mjs`, `npm run build`, and rollback SQL in `supabase/tests/admin_alerts.sql`. Security advisors flag the two private tables as RLS without policies by design: direct table privileges are revoked and guarded functions provide access.

Not implemented by this change: full business overview, automatic approvals, daily summaries, provider-wide payment failure monitoring, statutory deadline calculation or external delivery webhooks. Existing manual financial/compliance reviews remain required.

Sources: https://resend.com/docs/api-reference/emails/send-email , https://resend.com/docs/dashboard/emails/idempotency-keys , https://supabase.com/docs/guides/functions/schedule-functions .

Production transport check: scheduler successfully authenticates and reports missing_resend_key until the owner supplies the Edge secret. Supabase safeupdate requires WHERE clauses even for singleton settings updates; the live scheduled request verifies that transport path. The managed SQL connection cannot load safeupdate directly. Existing unrelated security advisor warnings remain outside this change; the new guarded RPCs expose no definer functions in public.
