# Prediction and Betslip review policy

Betslip Pro V1 uses **automated validation + exception review**, not manual approval for every submission.

## Default publication flow

A submission can auto-publish when the seller is eligible and all automated checks pass. The checks should confirm required fields, future kickoff, valid odds, no duplicate selections, acceptable price/odds sanity, selected bookmaker where required, active seller agreement and an eligible tipster account. Published content is immutable.

Uploaded screenshots are labelled **Uploaded Proof** automatically. They are not Betslip Pro Verified merely because an image was uploaded. Verification depends on selections being recorded and locked on Betslip Pro before kickoff.

## New tipster probation

New tipsters should normally have their first **3–5 submissions** routed through manual review. After successful probation, KYC/verification, good conduct and satisfactory platform history, they can receive **Trusted Tipster / Auto-Publish** eligibility.

## Exception queues

Admin/reviewer work should focus on three queues:

1. **Needs Review** — probation submissions, failed sanity checks, abnormal odds or pricing, duplicates, incomplete integrity signals or other publication exceptions.
2. **Reported** — buyer/user reports that require moderation.
3. **Suspicious Activity** — unusual win-rate patterns, repeated risky behaviour, integrity flags or other fraud/abuse signals.

A Trusted Tipster submission that passes automated validation should not wait for a human reviewer.

## Reviewer permissions

`/review` remains a bilingual authenticated exception-review workspace. Superadmins can enable/revoke scoped reviewer access and every change is audited. Reviewers may inspect flagged/pending submissions, approve/publish or reject with a review note. Snapshot revision checks prevent approving content changed since review. Existing publication immutability applies.

Jimmy's existing reviewer grant remains scoped to review access unless separate finance/admin permissions are granted. Reviewer access by itself does not grant support, finance, KYC or settlement permissions.

## Results

Where reliable settlement data is available, published predictions/betslips should update automatically to **Won / Lost / Void**. Manual settlement is reserved for exceptions and disputed/ambiguous results.

## Operational principle

Admin is an **exception reviewer**, not a gatekeeper for every betslip. This keeps V1 fast while preserving fraud, quality and compliance controls.
