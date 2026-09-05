# Brand Partnerships operations

The public /advertise page links to /advertise/partnerships. Verified account holders who accept current policies can submit a business brief, sector, proposed budget, dates and placement. This is a separate inquiry, not an approved advertiser application, paid booking or active campaign. Five requests per account per 24 hours are permitted.

Active admins review /admin/partnerships and save applicant-visible responses with reviewing, proposal or closed status. A proposal is not a signed agreement. Review actual inventory, deliverability and reporting before quoting. Bookmaker inquiries need additional compliance review before any agreement or publication. No email is sent automatically; applicants read replies in their account. No brands are represented as existing partners.

The private partnerships.requests table is inaccessible directly to API roles. Public invoker RPCs call guarded functions in the non-exposed partnerships schema. Owners read only their own requests; active admins read the queue and reply. Submissions, admin reads and reviews are audited. General account identity/payment/KYC access is not expanded.

Requests contain account-linked business data: include them when an operator processes a data access, correction or deletion request. No retention duration is presented as statutory. Until a retention schedule is approved, no automatic purge runs. On an approved deletion request, the privacy operator reviews partnerships.requests for this user and removes or redacts business/objective/response data unless a documented financial, dispute or legal hold requires retention; preserve the minimum necessary audit evidence. Do not put identity documents or payment credentials in these fields.

Validation: production Next.js build/TypeScript passed. Hosted transactional test brand_partnerships.sql passed with rollback: valid submission, invalid-input rejection, owner isolation, non-admin denial, direct-table denial, applicant-visible response and audit evidence. No test campaigns or users retained.
