# KATARINA AI — Public Research Update Policy

This directory contains **only public-facing website copy** and a curated public update feed. It is not the trading research workspace.

## Publication gate (mandatory)

1. Confirm a real change with public GitHub repository evidence or a direct, explicitly authorized project status from the user. Do not infer progress from plans, chat enthusiasm, or unverified simulations.
2. Write only a brief **high-level** milestone and its evidence reference. Use truthful verbs such as planned, under development, or verified, with no exaggerated claims.
3. NEVER disclose strategy algorithms, code snippets, indicators/parameter combinations, source datasets or tick files, data suppliers, model weights, feature engineering, prompts, repository/private paths, infrastructure hosts/ports/secrets, access tokens, account IDs, license keys, trading lot/entry/SL/TP settings, trading balances, personal data, client information, confidential performance, or private reports.
4. Do not publish a win rate, backtest score, historical or live return, broker-specific information, a release date, or sponsor approval unless it has been separately independently verified and the user explicitly cleared it for publication.
5. Updates should have translations for all supported language codes (en, id, es, fr, pt, de, ar, hi, zh, ja, ko, ru, ms, tr) or use reviewed neutral event keys already included in the website. If unsure, do not publish.
6. Source of truth: this website's `updates.json`, and mirrored production file on Vercel project `katarina-research`. No update is public until the production website is redeployed and independently tested. Prefer minimal writes: only publish when a **material, verified** safe update exists; never commit per hourly check.
7. Sponsor donations are not accepted until GitHub Sponsors approval is verified with a publicly reachable functioning sponsor page. No investment-return language or profit guarantees.

This policy must be applied to any automated job that edits or deploys this public page.

## Trading journal and weekly market research

- The public UI reads `website/reports.json`. It is a **curated publication queue**, not raw trading storage. Empty arrays mean no approved report is publicly available; do not fill them with samples presented as real trading history.
- For each daily or weekly entry, require reliable source evidence, documented independent verification and explicit permission to publish. Set `verified: true` and `approvedForPublication: true` only after both checks. Use `date` (YYYY-MM-DD), `mode` (one of `backtest`, `demo`, `live`), `verification` (non-sensitive audit description), and a `summary` in each of the website's 14 languages.
- Only aggregate and already-cleared performance metrics may be released. Keep simulated, demo and live data separate and conspicuously labeled. Never mix modes in one published performance curve.
- Strictly exclude raw orders, positions, lots, exact entry/exit settings, trading account identifiers or balances, brokerage details, source trading data, strategies, models, secrets and unpublished tests. Treat absence of verification as absence of a public result.
- For a publication deployment, preserve **all three files** `website/index.html`, `website/updates.json` and `website/reports.json` in the same Vercel project; a GitHub commit by itself does not publish to this project's source-inline production deployment. Verify that the live page and both feeds match after deployment.

## Monetization readiness gate

- Public `plans.html` is an interest/quote catalogue. Display hypothetical/indicative prices with explicit "not yet available" status; no active payment buttons or implied entitlement.
- GitHub Sponsors is NOT marked active until the public sponsor page, receiving account and payout status are independently verified. Only then place a real `.github/FUNDING.yml` username and activate Sponsorships in repository settings.
- No client email addresses, payments, license tokens, transaction records or proprietary strategy source may be committed to public GitHub.
- Paid technical service inquiries may use a mailto link but require a written quote, scope, acceptance and a verified payment method before fulfillment.
- Changes to the GitHub repository do not deploy the independently maintained Vercel production project automatically. Publish there only after validating the entire static asset bundle; do not publish a partial update that breaks assets.
