# Betslip Pro compliance and authentication — 5 September 2026

## Implemented and verified

The existing Next.js/Supabase application is retained. Five hosted database migrations have been applied to the existing Betslip Pro project `iqdgtnwgphqstpazquku`, with matching files under `supabase/migrations`:

- `20260905130743_compliance_privacy_auth.sql`
- `20260905130946_compliance_privacy_hardening.sql`
- `20260905131112_seller_identity_onboarding.sql`
- `20260905131208_restricted_profile_writes.sql`
- `20260905131510_private_signup_name.sql`

Do not reapply them to this project. `supabase/upgrades` contains authoring copies, not additional migrations. Earlier source migration filenames do not all match historical hosted timestamps; reconcile migration history before a CLI push to an existing project.

Seven bilingual policy pages live under `/legal`: Privacy, Terms, separate Seller Agreement, Refund/Cancellation, Responsible Use/18+, Community Guidelines and Cookies. Current text is in `lib/policies.ts`, version `2026-09-05`. Do not edit released policy text in place: archive it, publish a new version and update the database's acceptance/version checks together. Existing acceptance records are append-only with server timestamps. No historical acceptance was fabricated for existing customers.

`/account/privacy` provides current acceptance, private name/contact corrections, a downloadable account/transaction subset, persistent access/correction/deletion requests and their resolutions, and Google/Apple identity linking. Users must explicitly acknowledge Terms/Privacy/18+ after verified sign-in. Buying and seller submissions/publication are gated in the database as well as in the application. Seller acceptance creates a pending tipster profile on the same account if needed; administrative approval remains separate.

Private signup names are not automatically copied into new public tipster display names. Public tipster fields are separate from owner-only account/payment records. KYC uses references to a separately secured provider, never identity images in a public bucket. The `compliance` schema is not an exposed Data API schema. Direct table access is denied. Privileged implementations live there, with invoker RPC wrappers and explicit authorization checks. Do not add this schema to exposed schemas.

`/admin/compliance` supports evidence-backed PDPC, Gaming Board, tax, retention and operator-contact configuration; privacy case review; account restriction/minimization; KYC reference review; retention cleanup; audited restricted reads; and staff permission assignment. All start unconfirmed. A setting is an operator record, not regulatory approval. Confirmed tax configuration requires rate, base and gross-up explanation and evidence, but does not automatically compute or remit tax.

Only an active super admin assigns privacy, finance, KYC and configuration scopes to existing admins. Super admin has all scopes. Ordinary moderation admin cannot read private account data, audit logs, KYC, or payment references. Payment review/refund/earnings-release functions require finance scope. Audited reads return at most 200 cases/payments/accounts at a time; larger operations currently require an authorized server-side export/review, not an unrestricted browser dump.

Sensitive reads and changes produce audit records; profile/payment/wallet/tipster updates log changed field names rather than new private values. Auth events are handled by Supabase Auth. Never put tokens, passwords, identity images or excessive personal data in access reasons/resolutions.

Prediction/Betslip remain the core content types. Simple bookmaker labels, TZS 1,000 illustrative payout, immutable published records and separate processing fees preserve the agreed model. Commission is still 70% tipster / 30% platform. Uploaded Proof never independently earns Verified status; this change does not introduce an external proof-import pipeline. Approval of a tipster is no longer falsely described as an identity verification.

## Google and Apple: exact owner configuration

Credentials were not supplied or provisioned in this task. Buttons are disabled when Supabase reports the provider is not enabled. They call real Supabase OAuth, not demo sign-in.

### Shared configuration

1. Supply the deployed application origin as `NEXT_PUBLIC_APP_URL` before building, e.g. the owner's actual HTTPS origin. This is public configuration, not a secret. The local tested origin is `http://localhost:3034`.
2. In Supabase Auth URL Configuration set the production Site URL and allow the application's exact `/auth/callback` URL, plus the necessary query variants for safe `next` paths. For development allow `http://localhost:3034/auth/callback` and corresponding query variants. Do not broadly allow unrelated origins.
3. Keep email confirmation enabled, anonymous sign-in disabled, configure SMTP/rate limits, and review leaked-password protection (currently reported disabled by the advisor). No phone OTP implementation existed, so email/password is preserved; phone on the privacy form is contact data, not a verified authentication identity.
4. Enable manual identity linking in Supabase Auth for the signed-in Link Google/Apple controls. Supabase handles automatic verified-email linking and provider identity uniqueness; the app never merges users using an email from a client payload. For an existing identity conflict, sign in to the existing account and link from Account / Privacy. Never merge purchases or transfer ownership based on email matching alone. Different Apple relay/email identities cannot be assumed to represent one person.
5. Keep `NEXT_PUBLIC_SUPABASE_URL` and the project's public anon/publishable key configured. Existing code uses `NEXT_PUBLIC_SUPABASE_ANON_KEY`. `SUPABASE_SERVICE_ROLE_KEY` and bootstrap/settlement secrets, when needed by existing server routes, must stay in server environment variables. Nothing containing a provider secret belongs in `NEXT_PUBLIC_*`.

### Google

Create an OAuth Web Application in Google Cloud for this product. Configure consent-screen branding and authorized domains, and authorized JavaScript origins for the actual HTTPS app origin (plus localhost for development if applicable). The **Google authorized redirect URI** is:

`https://iqdgtnwgphqstpazquku.supabase.co/auth/v1/callback`

Provide Google **Client ID** and **Client Secret** in the Supabase Google provider configuration. Do not place the Google secret in application source or browser configuration. Confirm the consent screen is published/approved as required for the intended audience.

### Apple

The owner needs an Apple Developer account, a primary App ID with Sign in with Apple enabled, a web **Services ID** associated with it, **Team ID**, **Key ID** and the downloaded **.p8 private key**. Configure the domain and web return URL for the Supabase callback:

`https://iqdgtnwgphqstpazquku.supabase.co/auth/v1/callback`

Set the Services ID as the Apple OAuth client identifier in Supabase. Generate the Apple client-secret JWT server-side using Team ID, Key ID and .p8 key, and store it only in Supabase's Apple provider secret configuration. Rotate the secret before expiry; Supabase's Apple web OAuth guidance documents a maximum six-month interval. Configure Apple's private-email relay delivery as needed for account mail. The application does not depend on Apple returning a full name on every sign-in.

The provider callback above differs from the app callback `https://<actual-app-origin>/auth/callback`; configure both in their respective consoles. Custom Supabase auth domains require using the actual callback shown in that project's dashboard.

### Owner sign-in acceptance checks

After configuring each provider, test a new user, a returning user, existing verified-email account, Apple Hide My Email, explicit linking from a signed-in account, identity already linked elsewhere, consent cancellation, expired callback/PKCE, page refresh, logout and a second device. Confirm one `auth.users.id` and one profile per linked verified identity, no role escalation, and no paid-content access before verified payment. These external-provider journeys could not be executed without credentials.

## Retention and deletion runbook

No statutory retention duration or WHT calculation has been guessed. Before launch, the responsible privacy/legal/finance owners must record a schedule covering the data categories, purpose/legal basis, trigger, period, hold conditions, owner, storage/processor location, cross-border safeguards, backups and deletion evidence in the retention setting with an approval reference.

- **Public profile/private contact:** correction is immediate. A reviewed deletion request can restrict the account and replace identifying public/private profile fields, remove follows/notifications and revoke refresh sessions. Published history is attributed to Former tipster.
- **Auth identity:** the parent profile/auth identity is not blindly deleted because financial and immutable records depend on it. The reviewed workflow must finish identity minimization/soft deletion with the privileged Auth API after checking dependencies and retention obligations. Do not mark the case completed until this work is done, or use partially_completed with a precise explanation.
- **Public profile photos:** clearing the profile URL does not delete the existing storage object or CDN copies. Locate the account's files in `tipster-profiles`, remove through the storage API after review and request cache expiry as appropriate; record completion. No SQL deletion of `storage.objects` is used.
- **Financial records, disputes, consent and audit:** retain with a documented lawful justification/hold; avoid cascading account deletion. No automated purge is shipped for these ledgers. Periodically review the approved schedule and record any continued retention and eventual controlled archival/purge.
- **KYC:** keep only a provider reference, status, retention deadline and hold in the restricted table. Authorized cleanup removes expired references only after retention is confirmed, excluding holds/open privacy cases. It does not delete the external provider's records. Obtain and record provider deletion evidence separately.
- **Backups/logs:** document provider lifetimes and restoration procedures; prevent reactivation of deleted accounts on restore. Revoked refresh sessions do not retroactively invalidate all issued JWTs; restricted accounts are denied trading and profile changes, while retained own-record access supports privacy requests. Configure a suitable JWT lifetime and review incident/session revocation procedures.

A deletion request is a real tracked operational case, not a promise that every data copy disappears immediately. No live user's data was deleted in testing.

## Cookies

This release only uses necessary auth/PKCE cookies and language preference storage. No optional analytics/ad tracker is loaded, so there is no misleading Accept All banner. If optional tracking is later added, block it until a separate granular, revocable consent mechanism is implemented and the policy updated. Account terms acknowledgement is not marketing consent.

## Regulatory and launch status

PDPC registration, Gaming Board classification/licensing, TRA treatment, operator legal identity/contact, retention periods and international data-transfer arrangements require the owner's documented confirmation. The policies are product-specific implementation text requiring that final legal/operator review, not a claim of legal approval. The product does not accept betting stakes or pay winnings.

Frontend source and a local preview are delivered; this task does not publish the new frontend to the production domain. Deploy the synchronized application with the database changes before public use. Payments retain the existing manual Selcom verification and payout process; no real payment was initiated. Sports-results provider setup remains an existing separate production requirement.

## Validation

- Production build and TypeScript checks passed.
- Hosted transactional `supabase/tests/compliance.sql`: consent gates, wrong versions, append-only acceptance, private row isolation, admin scope checks, finance authorization, audit evidence, account restriction and retained purchase/consent records passed.
- Hosted transactional `compliance_admin.sql`: configuration validation, contact projection, KYC access, legal holds and expiry cleanup passed.
- Updated `focused_v1.sql`: publication/selection immutability, effective settlement odds, windows, ratings, 70/30 accounting, processing fees and integrity reviews passed.
- SQL fixtures rolled back. Legacy fixture suites without consent setup need the same current-policy setup before being run against this release.
- Browser: desktop policy, Kiswahili switching, 390px policy and 320px sign-in layout, unauthenticated privacy redirect, disabled unconfigured provider buttons and cancelled OAuth callback/error display. Authenticated pages are protected and were validated at the database layer; provider credentials are still needed for full end-to-end sign-in testing.
- Security advisor: new private tables intentionally have RLS with no client policies; new privileged logic is unexposed and public wrappers are invoker functions. Earlier aggregate/administrative SECURITY DEFINER RPCs still produce advisor warnings and have explicit role/data restrictions. Leaked-password protection remains an owner Auth configuration item.

## Official references reviewed

- [PDPC Personal Data Protection Act](https://www.pdpc.go.tz/media/media/THE_PERSONAL_DATA_PROTECTION_ACT.pdf)
- [PDPC collection and processing regulations](https://www.pdpc.go.tz/media/media/GN_NO._449C_OF_2023_3_1_2_TJPKuyC.pdf)
- [Gaming Board licence procedures](https://www.gamingboard.go.tz/publications/licence-procedures)
- [Supabase Google OAuth](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase Apple OAuth](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking)
- [Supabase SSR](https://supabase.com/docs/guides/auth/server-side/creating-a-client)

No TRA rate/base/gross-up determination is asserted. Record the applicable written tax advice before configuring that treatment.
