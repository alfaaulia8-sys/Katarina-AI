# KATARINA AI — Cloudflare Pages (Free) migration

## Objective
Host the public static website in `website/` on Cloudflare Pages Free without turning off the current Vercel deployment. This migration does not add advertising scripts, subscriptions or paid infrastructure.

## One-time user account authorization
Cloudflare is **not yet connected** in ChatGPT. The account holder must log into Cloudflare and authorize its GitHub integration, including access to `alfaauliau-katarinaAI/Katarina-AI`, if prompted. NEVER paste passwords, OTP, tokens or API secrets into chat. Do not authorize unrelated private repositories.

Go to https://dash.cloudflare.com/ → **Workers & Pages** → **Create application** → **Pages** → **Connect to Git** → GitHub.

Settings:
- Project name: `katarina-research` (if available; Cloudflare assigns the actual `*.pages.dev` hostname)
- Repository: `alfaauliau-katarinaAI/Katarina-AI`
- Production branch: `main` (confirm the repo default branch before saving)
- Framework preset: None
- Repository root directory: `/` (or default; don't change to `website` and also output `website`)
- Build command: `exit 0` (or leave blank, as the site is already built)
- Build output directory: `website`
- Environment variables: none needed for this public static site
- Plan: Free; do not enroll in paid services without the owner's approval.

Cloudflare Pages Git integration automatically creates deployments on pushes. Do not create a second scheduled automation: the existing consolidated 3-hour KATARINA research job can update validated public GitHub assets only when evidence changes. Cloudflare will then deploy on GitHub changes. The GitHub commit workflow must include the full public website folder, not expose VPS/MT5 source or private dataset.

## QA checklist BEFORE switching DNS
1. Wait for Cloudflare status **Success** (deployment URL genuinely issued by Cloudflare).
2. Compare `/`, `/analisa.html`, `/research.html`, `/journal.html`, `/insights.html`, `/privacy.html` and all existing navigation pages to Vercel.
3. Verify /market-ohlc.json, /calendar-brief.json, /instrument-context.json, /reports.json, /terminal.css, /terminal.js, /terminal-tools.js and SVG logo are available on the Cloudflare host.
4. On Android/mobile, test 34-instrument selector and keyboard search, synced Research → Analysis links, Canvas candlesticks, live source attribution and the 7-stage workflow details.
5. Verify no synthetic profit, forecast, buy/sell signal, account data, or secret parameters were inserted.
6. Confirm publisher SEO canonical URLs: currently the canonical URL intentionally points to the existing Vercel public domain. Do NOT switch these to Cloudflare before a real production hostname is known and approved. When moving the canonical domain, update all HTML canonical tags, OpenGraph urls, sitemap.xml and robots.txt together; then set proper redirects if the old domain can be controlled.
7. Confirm AdSense eligibility for the eventual domain in Google publisher documentation. `*.pages.dev` addresses are not guaranteed acceptable for AdSense registration. No ads.txt placeholder, invalid ad-click incentives or ad scripts without a real approved publisher ID.

## Costs, quotas, and failback
Cloudflare Pages Free currently includes 500 builds/month. Check Cloudflare's actual terms and any usage warnings. The site is static; no always-on server needed. The project's 3-hour schedule is a review cadence, not a requirement to redeploy unchanged content (max. ~248 review cycles/month).

Keep Vercel running as fallback until QA passes and the owner approves a DNS/canonical move. Never switch DNS/hosting for MT5 services or the separate VPS. No paid Cloudflare plan, domains, ads or third-party subscription without explicit approval.

Reference documentation:
- https://developers.cloudflare.com/pages/framework-guides/deploy-anything/
- https://developers.cloudflare.com/pages/configuration/git-integration/
- https://developers.cloudflare.com/pages/platform/limits/
