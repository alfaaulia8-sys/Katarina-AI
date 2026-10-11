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
