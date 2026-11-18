# psfdx website

The public one-page site for psfdx (psfdx.com). It is plain HTML, CSS and a few lines of JavaScript with no framework and no dependencies. It is not part of the PowerShell product: it never ships in the Gallery package and changing it does not cause a release.

```
site/
  src/               the page: index.html, style.css, script.js, favicon.png, og-image.png, _headers
  site.config.json   domain and link settings
  build.mjs          builds site/dist (needs Node 18 or later, nothing to install)
  build.test.mjs     tests: links and files exist, copy, accessibility basics, no outside requests
  Make-SiteImages.ps1  makes og-image.png and favicon.png from the original logo (Windows only, rarely needed)
```

## The logo

The site uses the repository's own `images/psfdx-logo.png`, unchanged. The build copies it into `site/dist/`, byte for byte, and a test checks that. There is deliberately no second copy of the logo in `site/`. `og-image.png` (the social sharing card) and `favicon.png` place and crop that same file; the logo is never redrawn.

## Build and preview

```bash
node site/build.mjs          # writes site/dist
node --test "site/*.test.mjs"
npx serve site/dist          # or any static file server; the page uses root-relative paths such as /style.css
```

Opening `site/dist/index.html` straight from disk will not show the styles, because the paths start with `/`. Use a server.

## Settings

`site/site.config.json` holds `siteUrl`, `githubUrl`, `licenseUrl` and `galleryUrl`. The build writes them into the page, `robots.txt` and `sitemap.xml`. To build for another domain without editing the file, set `SITE_URL`:

```bash
SITE_URL=https://example.org node site/build.mjs
```

## Deploy to psfdx.com (Cloudflare Pages)

The domain is registered at Cloudflare, so Cloudflare Pages is the simplest host (free for a site like this). One-off setup, in the Cloudflare dashboard:

1. **Workers & Pages → Create → Pages → Connect to Git**, and pick the `tonygward/psfdx` repository.
2. Production branch: `main`. Framework preset: **None**.
3. Build command: `node site/build.mjs`. Build output directory: `site/dist`. Root directory: leave empty (the repository root, because the build reads `images/psfdx-logo.png`).
4. Environment variable (optional): `NODE_VERSION` = `22`.
5. After the first deploy: **Custom domains → Set up a custom domain → `psfdx.com`**. Because the domain is already on Cloudflare, it adds the DNS record for you. Add `www.psfdx.com` as well and redirect it to `psfdx.com` if you want both to work.

Every push to `main` redeploys the site, and pull requests get a preview URL. To move to another host later, upload `site/dist/` anywhere that serves static files. The `_headers` file (security headers and caching) is understood by Cloudflare Pages and Netlify. On another host, set the same headers in its own configuration.

## Changing the content

Edit `site/src/index.html` and `style.css`, then run the tests. Keep the capability descriptions in line with the README and the real cmdlets, and do not state version numbers on the page, because they go stale. The footer disclaimer (not affiliated with or endorsed by Salesforce) must stay.
