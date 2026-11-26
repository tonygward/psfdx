# psfdx website

The public website for psfdx (psfdx.com), with a homepage and a documentation page for each included module. It is plain HTML, CSS and a few lines of JavaScript with no framework and no dependencies. It is not part of the PowerShell product: it never ships in the Gallery package and changing it does not cause a release.

```
site/
  src/               the homepage (index.html), module reference pages (modules/*/index.html), style.css, script.js, fonts/, favicon.png, og-image.png, _headers
  site.config.json   domain and link settings
  build.mjs          builds site/dist (needs Node 18 or later, nothing to install)
  build.test.mjs     tests: links and files exist, copy, accessibility basics, no outside requests
  Make-SiteImages.ps1  makes og-image.png and favicon.png from the original logo (Windows only, rarely needed)
```

## Design and fonts

The homepage follows the "psfdx.com Homepage Redesign" handover (21 November 2026): navy console palette, a typing terminal, a rotated command marquee, three feature cards, an eight-module list and a yellow closing panel. The prototype itself is not deployed; the page is plain HTML, CSS and a small script.

- **Fonts are self-hosted** in `src/fonts/` (Bricolage Grotesque and IBM Plex Mono, latin subset, both under the SIL Open Font License 1.1, downloaded from Google Fonts). The content security policy allows only this site, so no font is loaded from outside.
- **The release pill** shows the number in the repository's `VERSION` file, put in at build time (`%RELEASE_VERSION%`). Cloudflare Pages rebuilds on every push to `main`, and every release is a push, so it follows the latest release. It is the only version number allowed on the page.
- **The command marquee** lists real commands; a test fails if one stops being exported by a module.
- **Motion:** with `prefers-reduced-motion` the typing, float and marquee are off and the finished console is shown.
- **The console data is made up** and labelled as a sample.

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

Edit `site/src/index.html` and `style.css`, then run the tests. Keep all the module descriptions and their documentation pages in line with the README and the real cmdlets, and do not type a version number into the page: the release pill takes it from `VERSION` at build time. The footer disclaimer (not affiliated with or endorsed by Salesforce) must stay.

## Deployment troubleshooting

If a merge to `main` does not appear on psfdx.com, check the Cloudflare Pages `psfdx` project's deployment history and GitHub connection. Cloudflare Pages must automatically build `main` with `node site/build.mjs` and publish `site/dist`; GitHub's `ci-site.yml` validates pull requests but does not publish the site. If no deployment is created for the commit, investigate the GitHub integration rather than the site build. After reconnecting the repository, verify that a subsequent push creates a new production deployment.

<!-- Deployment trigger verified after granting the Cloudflare GitHub App access to psfdx on 2026-11-21. -->

## Module documentation

The homepage links to `/modules/<module-name>/` for each module (every module that exports commands). `psfdx-shared` is internal: it exports nothing, so it has no page, no homepage row and no reference. The pages are a short introduction followed by a command reference. The introductions (definition and overview) are written by hand in `site/src/modules/<module>/index.html`; the main `psfdx` page also keeps its installation instructions and showcase examples.

The command reference is generated from native `Get-Help`. `site/Update-ModuleReference.ps1` imports the repository modules and fills the region between `<!-- reference:start -->` and `<!-- reference:end -->` on each page. Every entry has the same sections in the same order: **Synopsis, Syntax, Description, Parameters, Salesforce CLI, Examples, Remarks, Related Links** (Parameters is left out for a command with none). There is no NAME section, because the command name is the heading, and no Inputs or Outputs section; native `Get-Help` is unchanged. The Examples section shows the first example with the `PS>` prompt, and cmdlets without a direct CLI command say so in the Salesforce CLI section.

The same script writes the **GitHub Markdown reference**, `docs/reference/<module>.md` with an index in `docs/reference/README.md`. The website entry and the Markdown entry are rendered from one model per command, and the section order is one list in the generator (`$referenceSections`), so the two cannot differ. The Markdown shows the same content as the website: same commands in the same order, same synopsis, parameters, Salesforce CLI commands, example lines and links.

A command appears under the module that exports it, so moving a command to another module moves its entry. Run `pwsh ./site/Update-ModuleReference.ps1` in an English PowerShell session after changing a command, its help, or its owning module, and commit the changed pages and Markdown. `site/ModuleReference.Tests.ps1` fails when a page or a Markdown file is stale or the section order or content drifts between them, and also checks that every command is documented once under its owning module, that every `sf` command shown exists in the CLI inventory, and that every wrapped `sf` command appears on a page. `site/build.test.mjs` checks the structure of the pages and that every exported command has an entry.

Never edit between the markers by hand: the next run replaces it. Larger modules group commands by the Salesforce feature they work with. The group names and matching rules live in the generator. A small script, `reference.js`, opens a command when the page is loaded with its fragment identifier.
