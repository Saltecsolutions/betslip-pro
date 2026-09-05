# Jimmy's weekly update

Recipient: jdaking08@gmail.com. Weekly Monday at 09:00 Africa/Dar_es_Salaam (06:00 UTC). First scheduled run after rollout: 7 September 2026. No immediate introductory email is sent.

The report covers the previous Monday 00:00 through the following Monday 00:00, Tanzania time. It includes only aggregate counts: new profiles excluding current admin roles, distinct tipsters who published content, published Prediction/Betslip records, purchases verified in the period that remain paid at snapshot time, and new partnership requests. It shares no money amounts, personal details, KYC, private briefs or admin access. It makes no claims about deals signed or product work completed. Product plans and narrative progress require Salmin's input.

The snapshot is stored once per week in the private outbox. Retries use the unchanged snapshot and existing Resend idempotency/lease protections. The partner recipient is fixed in the server email template; other event types remain routed only to Salmin. Delivery status appears in the superadmin email activity list. A superadmin can pause future weekly report generation on /admin/alerts; existing queued reports may still send. The main pause stops all email delivery. Resuming does not create reports for missed weeks.

The report uses current record state at generation time, so later corrections/refunds are not retroactively applied. It is an operational activity summary, not an accounting statement. Future week generation is pg_cron in the project database and does not depend on this chat running.

Validation: node tests verify recipient isolation and no sensitive/free-form fields in the email; rollback SQL checks snapshot/week boundaries/deduplication/permissions; Next build/typecheck passes. No test email has been sent to Jimmy and his inbox delivery is not yet verified.
