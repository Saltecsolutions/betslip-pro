# Feedback intake

Public entry: https://www.betslip.co.tz/feedback

Google Form: https://docs.google.com/forms/d/e/1FAIpQLScHoTX_6tOxpfK-p9GdPOU93B1scdyoG16_X9i6rsr8J_3YWg/viewform

Owner editor: https://docs.google.com/forms/d/18mv8OhIvuH0HUVsXcs4UN5DzuSieLsKVDDKTpmQWjhA/edit

Private tracker: https://docs.google.com/spreadsheets/d/1DT-NP2DCBuoqd4Hm_4IgyD8UanbdUim2rWaoGsGWx2g/edit

## Behavior

Google Forms writes directly to its linked `Form Responses 1` sheet. No app API secret, service account, or background synchronization is needed. The form is published for anyone with the link; Google sign-in is not required. Automatic email collection, draft autosave, response editing and public response summaries are disabled. Contact email is a separate optional field.

The app loads the third-party iframe only after the user chooses to open it. An external-tab link remains available when embedding or third-party storage is blocked. The native Google form controls its own language for interface elements; question labels and the app page use English and Kiswahili. Form confirmation means a response was recorded, not resolved.

## Owner workflow

- A:D are native form data: timestamp, category, details, optional email. Do not rearrange form questions or response columns without rechecking the status formula.
- E (`Badilisha status`) is an editable native dropdown: Mpya, Inakaguliwa, Inafanyiwa kazi, Imekamilika, Imefungwa.
- F is the assigned team member's name; G is internal notes.
- H (`Status`) computes Mpya for new responses with blank E, otherwise displays E. Its array formula is anchored in H1 and references whole A/E columns so new inserted form rows are included. It is outside the sortable native table and recalculates from each row. A warning protects it from accidental edits.
- Use the entire table's filters/sort; never sort an individual column. Do not paste into column H.
- The `Mwongozo` tab explains the workflow in Kiswahili.

Status changes are internal only. They do not send email, notify Jimmy, or provide a customer-facing ticket lookup. The Sheet is private to salmin@saltecsolutions.co.tz. Assigning a name does not grant access. Any subsequent sharing should be limited to authorized feedback handlers.

## Privacy and operations

Do not copy passwords, KYC documents or payment data into this tracker. Route refunds and personal-data requests through existing account controls. Contact details are used only for follow-up. This external store is not automatically included in the account deletion workflow: authorized staff must check both Google Forms responses and its linked Sheet when processing an applicable access/correction/deletion request, preserving only records that have a valid retention basis. Deleting from the Sheet alone does not delete the original Form response. No automatic retention cleanup is configured for this tracker.

Form spam screening and quotas are Google-managed; there is no custom app CAPTCHA, per-account rate limit or app identity verification. Review irrelevant submissions before acting on them.

## Verification

2026-09-05: a clearly labelled SYSTEM TEST was submitted through the public responder form with no contact email. Its row appeared in the linked Sheet; H displayed Mpya. The test was subsequently marked Imefungwa in E with a closure note. Native dropdown metadata and private sharing were checked. The production Next build includes type validation.
