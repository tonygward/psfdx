import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, readConfig, applyConfig } from './build.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'psfdx-site-'));
const dist = path.join(out, 'dist');
build({ outDir: dist, env: {} });
const html = fs.readFileSync(path.join(dist, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(dist, 'style.css'), 'utf8');

test('the logo is the repository logo, byte for byte', () => {
  const original = fs.readFileSync(path.join(repoRoot, 'images', 'psfdx-logo.png'));
  assert.ok(fs.readFileSync(path.join(dist, 'psfdx-logo.png')).equals(original));
  assert.equal(fs.existsSync(path.join(here, 'src', 'psfdx-logo.png')), false, 'do not keep a second copy of the logo in site/src');
});

test('no placeholder is left in any built file', () => {
  for (const name of fs.readdirSync(dist)) {
    const text = fs.readFileSync(path.join(dist, name));
    if (/\.(png)$/.test(name)) continue;
    assert.doesNotMatch(text.toString('utf8'), /%[A-Z_]+_URL%/, name);
  }
});

test('the domain is configurable', () => {
  const other = path.join(out, 'other');
  build({ outDir: other, env: { SITE_URL: 'https://example.org/' } });
  const text = fs.readFileSync(path.join(other, 'index.html'), 'utf8');
  assert.match(text, /<link rel="canonical" href="https:\/\/example\.org\/">/);
  assert.match(text, /og:image" content="https:\/\/example\.org\/og-image\.png"/);
  assert.match(fs.readFileSync(path.join(other, 'robots.txt'), 'utf8'), /Sitemap: https:\/\/example\.org\/sitemap\.xml/);
  assert.throws(() => readConfig({ SITE_URL: 'http://insecure.example' }), /https URL/);
});

test('every local file the page refers to exists in the build', () => {
  const refs = [...html.matchAll(/(?:href|src)="(\/[^"#?]*)"/g)].map(m => m[1]).filter(r => r !== '/');
  assert.ok(refs.length >= 4);
  for (const ref of refs) assert.ok(fs.existsSync(path.join(dist, ref)), `${ref} is missing from the build`);
  assert.ok(fs.existsSync(path.join(dist, 'og-image.png')));
  assert.ok(fs.existsSync(path.join(dist, '_headers')));
});

test('the page has the approved copy, title, description and disclaimer', () => {
  for (const text of [
    'Salesforce. Meet&nbsp;PowerShell.',
    'Powerful Salesforce tools. Familiar PowerShell commands.',
    'A simpler, more intuitive way to work with Salesforce.',
    'Less time remembering CLI syntax. More time getting things done.',
    'PowerShell simplicity. Salesforce capability.',
    'psfdx is an independent open-source project and is not affiliated with or endorsed by Salesforce.',
    '<title>psfdx',
    '<meta name="description"',
    'Connect-Salesforce</span> <span class="p">-Sandbox</span> <span class="p">-SetDefault</span>',
  ]) assert.ok(html.includes(text), text);
  for (const area of ['Organisations &amp; Data', 'Metadata &amp; Deployments', 'Development &amp; Testing', 'Monitoring &amp; Diagnostics', 'Sandboxes &amp; Packages', 'Agentforce']) {
    assert.ok(html.includes(area), area);
  }
});

test('accessibility basics: language, one h1, skip link, alt text, labelled landmarks', () => {
  assert.match(html, /<html lang="en-GB">/);
  assert.equal((html.match(/<h1[ >]/g) || []).length, 1);
  assert.match(html, /class="skip-link" href="#main"/);
  assert.match(html, /<main id="main">/);
  for (const img of html.match(/<img\b[^>]*>/g)) assert.match(img, /\balt="[^"]+"/, img);
  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion/);
});

test('the page makes no outside requests and uses no inline script or style', () => {
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)/);
  assert.doesNotMatch(html, /\sstyle=/);
  assert.doesNotMatch(css, /url\(\s*['"]?https?:/);
  for (const m of html.matchAll(/<(?:script|link|img)\b[^>]*(?:src|href)="(https?:[^"]+)"/g)) {
    assert.match(m[0], /<link rel="canonical"|<link[^>]*og/, `outside resource: ${m[1]}`);
  }
});

test('the content security policy allows only the site itself', () => {
  const headers = fs.readFileSync(path.join(dist, '_headers'), 'utf8');
  assert.match(headers, /Content-Security-Policy: default-src 'self'/);
  assert.doesNotMatch(headers, /unsafe-inline|unsafe-eval|https?:\/\//);
});

test('claims stay accurate: no version number and no Salesforce endorsement wording', () => {
  assert.doesNotMatch(html, /\b\d+\.\d+\.\d+\b/);
  assert.doesNotMatch(html, /official partner|certified by|endorsed by Salesforce\.(?!<)/i);
});

test('applyConfig replaces every occurrence', () => {
  assert.equal(applyConfig('%GITHUB_URL% %GITHUB_URL%', readConfig({})), 'https://github.com/tonygward/psfdx https://github.com/tonygward/psfdx');
});

test('cleanup', () => { fs.rmSync(out, { recursive: true, force: true }); });
