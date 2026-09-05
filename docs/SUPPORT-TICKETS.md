# Support tickets

Customer: https://www.betslip.co.tz/support

Team: https://www.betslip.co.tz/support/team

## Operational behavior

- Verified, active customers create a ticket and receive a BP-number. Customer views and messages are isolated by account ownership in the database, not only the UI.
- Categories: account, technical, general, payment, purchased content and refund. Optional purchase links must belong to the caller. Refunds require an eligible purchase and create or reuse its existing dispute.
- Statuses: open, in_progress, waiting_customer, resolved, closed. Staff send a reply and choose status; a customer reply reopens the ticket. Internal notes do not notify customers or alter the customer-facing status.
- Request UUIDs prevent duplicate submissions/replies on retry. Existing active purchase/category tickets are reused. Limits: five new tickets per account/hour and ten messages per author/minute.
- Tickets are assigned automatically to eligible support agents, with active superadmins as fallback. General agents cannot read payment/content/refund tickets. Those require both support access and existing finance authorization. Superadmins have both.
- Staff queue has status/overdue filters, subject or ticket-number search and 50-row pagination. Conversation refresh is explicit, not a live-chat stream.
- Existing disputes were backfilled without historical notification/email floods. New disputes from the legacy Protection page also create tickets. Dispute updates post a system message: rejected/refunded resolves the ticket, approved keeps it in progress until transfer/review is completed. Ticket status never executes a refund. Closing an open/approved dispute ticket is rejected.
- Internal response targets are four hours for purchase-related tickets and 24 hours otherwise. Cron `betslip-support-escalation` runs at minute 15 each hour, flags overdue open/in-progress tickets, notifies the assignee and emails Salmin once per due cycle. Waiting-customer and resolved/closed tickets do not escalate. These are operational targets, not promised resolution times.

## Notifications and email

All support updates link to authenticated ticket pages through the existing Activity area. Customer email is explicitly selected in the new-ticket form and can be toggled on the ticket. Phone-only users continue with in-app updates.

The existing `admin-alerts` Edge worker now handles `support_customer` and `support_escalation`. No new credential is required. Sender is Betslip Pro <noreply@betslip.co.tz>. Customer recipients come only from the current confirmed auth email, never a ticket payload supplied by the browser. Before claiming a delivery, SQL checks the recipient is still current, the profile remains active and ticket email is enabled. Emails contain only the BP-number, sign-in link and instructions to reply inside the app; no subject, transcript, financial details or internal notes. Reply-by-email is not configured.

The existing outbox supplies leases, retries and stable Resend idempotency. The main email pause also pauses support mail. `/admin/alerts` shows queued/accepted/failed items without exposing customer addresses. Accepted means provider acceptance, not proof of inbox delivery. Resend holds delivery/bounce logs; automatic inbound replies and delivery webhooks are not implemented.

Jimmy has not been granted support access. An active superadmin can enable or revoke it using a verified registered email in Team → Support team access with an audit reason. This grant does not modify account roles or finance/KYC/privacy permissions. Access is checked live in SQL; old sessions cannot retain a revoked grant. Disabled assignees are replaced on the next routing event.

## Privacy and security

Tables are in private `support` schema with RLS enabled and all direct API table grants revoked. Only the invoker `public.support_api` wrapper is exposed; it calls a guarded private function. Customer ownership and team/category scopes are enforced for every operation. Staff queue/detail reads, grants, assignments, replies and escalations leave audit events without transcript bodies. Anonymous access is denied. No file uploads are accepted.

The existing account export now includes owned support tickets and customer-visible messages; internal staff notes are excluded. The existing authorized privacy-restriction workflow disables support emails, removes stored outbox recipient addresses, cancels pending support email, and redacts nonfinancial support transcripts and subjects. Those tickets become closed and cannot reopen. Purchase-linked, dispute-linked and payment/content/refund histories are retained for financial/compliance review, with existing audit events intact. No unsupported statutory duration or automatic financial deletion is assumed. Staff must apply the configured retention policy to retained records; no new automatic expiry was introduced.

Support is exempt from the transaction policy-acceptance redirect so a verified user can obtain help with account/consent problems. The backend still requires an active verified account. Signed-out visitors go through the existing sign-in flow and return to their ticket. Public Google Forms feedback remains available for suggestions, independent of ticket history; it does not sync tickets into the Sheet.

## Validation and rollout

- `supabase/tests/support_tickets.sql`: rollback-only generated identities; ownership and cross-user rejection, dedicated support scope, finance isolation, internal-note privacy, customer export, create/reply idempotency, email opt-out and overdue deduplication.
- `supabase/tests/support_finance.sql`: rollback-only purchases/disputes; refund creation/link/dedup, pending-refund closure guard, source dispute synchronization, nonfinancial redaction and financial preservation.
- `node --test supabase/functions/admin-alerts/handler.test.mjs`: 12 passing tests including safe customer payloads and fixed escalation routing.
- Production build/type validation passed. New support schema has only expected deny-by-default RLS-without-policy informational notices. Existing public function warnings and disabled leaked-password protection predate this change; see https://supabase.com/docs/guides/database/database-linter and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

Remote migrations were applied by the Supabase migration tool and mirrored locally with the exact migration-history versions. The installed CLI could not create a local migration because it tried to write telemetry outside the permitted workspace.
