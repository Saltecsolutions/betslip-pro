# Scoped prediction reviewers

`/review` is the bilingual, authenticated reviewer workspace. The account dashboard shows its link only to authorized reviewers. Superadmins can enable/revoke an email under Reviewer permissions; each change is audited. The server matches only the current confirmed email of an active account. A grant can precede registration. It never creates an account or accepts policies for anyone.

Jimmy's requested grant is enabled for jdaking08@gmail.com. At setup time no registered account existed. He must register/sign in with that exact email, verify it and accept the current account policies. No invitation was sent.

Reviewers can inspect complete pending predictions/betslips belonging to other tipsters and approve/publish or reject them with a review note. Publication still requires a future kickoff, valid odds, active tipster and current seller agreement. Snapshot revision checks prevent approving content changed since review; existing publication immutability applies. Reads and decisions are audited. Tipsters receive in-app outcome notifications.

This permission does not change the profile role, grant support/finance/KYC access, settle results or turn a submission into a verified winning record. Superadmins retain existing administrative powers. Revoke an email to immediately remove reviewer access (superadmin access is independent).

Validation: production build/typecheck; rollback-only database tests in `supabase/tests/prediction_reviewers.sql`. No real submission is published by these tests.
