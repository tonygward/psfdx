# WEB: High-fidelity website redesign from Claude Design handover

**Tracking issue:** https://github.com/tonygward/psfdx/issues/219

Written after the work, not run by Matrix. The task was picked up from the issue by hand and merged in pull request #223. Release: none (website only; psfdx.com redeploys from main).

## Objective

Replace the psfdx.com homepage with a high-fidelity implementation of the supplied Claude Design handover (21 November 2026).

## What was delivered

- The eight sections in order: header, hero, animated console, rotated command marquee, Why psfdx, six modules, closing CTA, footer; palette, 1240px width, tilt, float, marquee, typing and copy timings as specified.
- Plain HTML, CSS and a small script. Fonts (Bricolage Grotesque, IBM Plex Mono) are self-hosted because the content security policy allows only the site. The release pill is filled from `VERSION` at build time. The marquee commands are checked against the module manifests. Reduced motion shows the finished console and a static command list.
- Verified live after the Cloudflare Pages deploy: the new page is served, the CSP includes `font-src 'self'`, the fonts and stylesheet load, and a 500px-wide render has no sideways overflow. Not verified in a real browser: clipboard copy and tablet and true phone widths below 500px.
- The prototype archive was not available; the issue's transcribed specification was used. "Six modules" leaves out psfdx-agentforce. Known nit: `-Verbose` wraps inside its code chip on narrow screens.

## Tests

24 site tests: sections in order, hero copy, palette and type, timings, self-hosted fonts, CSP, accessibility, reduced motion, overflow rules, no outside requests, and the release number.

## Changelog

None: the website has no changelog entry.
