# KATARINA private onboarding registry

This directory is intended for **minimal registration metadata**, synchronized by the existing private `Katarina-VPS-Control` GitHub repository. The repository is private but should **not be treated as a credential vault**.

- `registration-profile.json`: non-secret reusable professional profile. Verify name, work history, contact preferences, and all claims before sending an application.
- `site-registry.json`: tracked websites, known status, registration history, and allowed workflow; statuses are *historical*, not proof of current login or platform approval.
- After an **authorized** new signup, update the registry with domain, date, site-specific contact email, and next action; commit once. Don't record passwords, session cookies, MFA codes, API tokens, or payment details.
- IDs, tax or financial paperwork, university files, and other sensitive documents **must not** be uploaded in plaintext to GitHub. Use local secure storage or separately encrypted backups if needed.
- VPS can read sanitized metadata and work on code, but freelance logins/marketplace submissions run only in an authorized environment and follow site rules. This profile does not authorize automatic bids, purchases, or contract acceptance.

Avoid storing client-confidential documents unless the client has authorized that storage.
