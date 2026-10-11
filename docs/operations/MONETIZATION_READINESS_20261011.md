# KATARINA AI — Revenue Readiness (11 October 2026)

## Current state
- Github main is a **public research development preview**, not a licensed or proven trading product.
- Github Sponsors account approval is still under review per existing public README; payout credentials/profile page unverified. **Do not enable checkout or represent Sponsors as active.**
- Website `plans.html` lists **indicative** Free, $9/month Research, $29/month Analyst, and $99 one-time EA plans. Each paid tier is interest-only, not an order form or entitlement.
- Technical services (Python/MT5 QA, data integration, documentation) accept **manual quotation inquiries** by email. No fees are automatically collected.

## How to activate paid subscriptions safely
1. Validate the actual service, deliverables, support/terms, refunds, privacy statement, and that financial advice is not implied.
2. Verify an authorized merchant / payment account and payout destination (do not put payout details, API keys, customer emails, orders, or secrets in public GitHub).
3. Implement provider-hosted checkout and server-side webhook verification, idempotent entitlement provisioning, revocation/cancellation, receipts, tax and chargeback support.
4. Reconcile sandbox payments, then complete an authorized production purchase/refund test before replacing the interest mailto with a checkout URL.
5. Track conversion, churn, refunds, and support cost separately from investment performance. Do not publish unverified P&L.

## How to activate GitHub Sponsors
1. Complete https://github.com/sponsors registration with the authorized GitHub owner, identity, tax and payout verification.
2. Independently verify that the recipient's **public** GitHub Sponsors page actually works. Do not post a broken link.
3. After approval, create `.github/FUNDING.yml` with the **approved and verified recipient's** GitHub username (e.g. `github: APPROVED_USERNAME`). Enable Settings → General → Features → Sponsorships. Verify the button while logged out.
4. Treat sponsorship as funding research/infrastructure, not an investment or returns-sharing offer.

## Source/privacy
- Public checkout pages contain only publicly approved descriptions. Keep strategy code, raw account data, models and secret configuration in private storage; an existing public Git history cannot be fully retracted.
- User's public site uses a separate Vercel **source-inline production deploy**. A repository commit does not automatically update that production domain.
- Preserve all static assets + `website/index.html`, `website/reports.json`, `website/updates.json` in any release; use a complete verified deployment bundle.
