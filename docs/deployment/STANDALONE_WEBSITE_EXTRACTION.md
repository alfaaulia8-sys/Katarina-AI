# Standalone website extraction (historical branch integration)

The old `web/standalone-extraction` branch intentionally deleted the Python,
MT5, governance and test trees to produce a separate website-only repository.
Those deletions do not belong in this unified repository. Current `website/`,
`functions/` and website scripts are retained, together with the complete AI code.
For a separate site repository, copy only those public site assets and keep its
README separate. The historical README used Cloudflare Pages, no build command,
output `website`, and public `/api/hot-news`. See [Pages setup](CLOUDFLARE_PAGES_SETUP.md).
Local `.dev.vars` and Wrangler dependencies are ignored here.
