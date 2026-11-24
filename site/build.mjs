// Builds the psfdx website into site/dist. No dependencies; needs Node 18 or later.
//
//   node site/build.mjs                          build with site/site.config.json
//   SITE_URL=https://example.com node site/build.mjs   build for another domain (no trailing slash)
//
// The logo is NOT duplicated in site/. The build copies the repository's own images/psfdx-logo.png, byte for byte,
// so the site always shows the one original logo.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fillPage, moduleDirs } from './reference.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..');

export const PLACEHOLDERS = {
  '%SITE_URL%': 'siteUrl',
  '%GITHUB_URL%': 'githubUrl',
  '%LICENSE_URL%': 'licenseUrl',
  '%GALLERY_URL%': 'galleryUrl',
  '%RELEASE_VERSION%': 'releaseVersion',
};

// The release shown on the page comes from the repository's VERSION file at build time, so it is never typed by hand.
// Cloudflare Pages rebuilds on every push to main, and every release bump is a push, so the page follows the latest release.
export function readReleaseVersion() {
  const version = fs.readFileSync(path.join(repoRoot, 'VERSION'), 'utf8').trim();
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`VERSION must be three numeric parts (got ${JSON.stringify(version)})`);
  return version;
}

export function readConfig(env = process.env) {
  const config = JSON.parse(fs.readFileSync(path.join(here, 'site.config.json'), 'utf8'));
  config.releaseVersion = readReleaseVersion();
  if (env.SITE_URL) config.siteUrl = env.SITE_URL;
  config.siteUrl = String(config.siteUrl).replace(/\/+$/, '');
  for (const key of Object.values(PLACEHOLDERS).filter(k => k !== 'releaseVersion')) {
    if (!/^https:\/\/[^\s"'<>]+$/.test(String(config[key] ?? ''))) {
      throw new Error(`site.config.json: "${key}" must be an https URL (got ${JSON.stringify(config[key])})`);
    }
  }
  return config;
}

export function applyConfig(text, config) {
  let out = text;
  for (const [token, key] of Object.entries(PLACEHOLDERS)) out = out.split(token).join(config[key]);
  return out;
}

export function build({ outDir = path.join(here, 'dist'), env = process.env } = {}) {
  const config = readConfig(env);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const srcDir = path.join(here, 'src');
  const copyDir = (fromDir, toDir) => {
    fs.mkdirSync(toDir, { recursive: true });
    for (const name of fs.readdirSync(fromDir)) {
      const from = path.join(fromDir, name);
      const to = path.join(toDir, name);
      if (fs.statSync(from).isDirectory()) { copyDir(from, to); continue; }
      if (/\.(html|txt|xml|css|js)$/.test(name) || name === '_headers') {
        fs.writeFileSync(to, applyConfig(fs.readFileSync(from, 'utf8'), config));
      } else {
        fs.copyFileSync(from, to);
      }
    }
  };
  copyDir(srcDir, outDir);
  // the command reference of every module page is built from the PowerShell source, so nothing generated is committed
  for (const dir of moduleDirs(repoRoot)) {
    const page = path.join(outDir, 'modules', dir, 'index.html');
    if (fs.existsSync(page)) fs.writeFileSync(page, fillPage(fs.readFileSync(page, 'utf8'), dir, repoRoot));
  }

  fs.copyFileSync(path.join(repoRoot, 'images', 'psfdx-logo.png'), path.join(outDir, 'psfdx-logo.png'));
  fs.writeFileSync(path.join(outDir, 'robots.txt'), `User-agent: *\nAllow: /\n\nSitemap: ${config.siteUrl}/sitemap.xml\n`);
  fs.writeFileSync(path.join(outDir, 'sitemap.xml'),
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n  <url><loc>${config.siteUrl}/</loc></url>\n${fs.readdirSync(path.join(srcDir, 'modules')).map(module => `  <url><loc>${config.siteUrl}/modules/${module}/</loc></url>`).join('\n')}\n</urlset>\n`);
  return { outDir, config };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const { outDir, config } = build();
    console.log(`Built the psfdx website for ${config.siteUrl} in ${path.relative(process.cwd(), outDir) || outDir}`);
  } catch (error) {
    console.error(`Build failed: ${error.message}`);
    process.exit(1);
  }
}
