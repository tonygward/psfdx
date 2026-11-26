import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, readConfig, applyConfig, readReleaseVersion } from './build.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'psfdx-site-'));
const dist = path.join(out, 'dist');
build({ outDir: dist, env: {} });
const html = fs.readFileSync(path.join(dist, 'index.html'), 'utf8');
const modulesPage = fs.readFileSync(path.join(dist, 'modules', 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(dist, 'style.css'), 'utf8');
const js = fs.readFileSync(path.join(dist, 'script.js'), 'utf8');
const release = readReleaseVersion();

// The exported function names of every psfdx module, read from the manifests.
const exported = new Set();
for (const dir of fs.readdirSync(repoRoot).filter(d => /^psfdx/.test(d) && fs.existsSync(path.join(repoRoot, d, `${d}.psd1`)))) {
  const manifest = fs.readFileSync(path.join(repoRoot, dir, `${dir}.psd1`), 'utf8');
  const block = manifest.match(/FunctionsToExport\s*=\s*@\(([\s\S]*?)\)/);
  for (const m of (block ? block[1] : '').matchAll(/'([^']+)'/g)) exported.add(m[1]);
}

test('the logo is the repository logo, byte for byte', () => {
  const original = fs.readFileSync(path.join(repoRoot, 'images', 'psfdx-logo.png'));
  assert.ok(fs.readFileSync(path.join(dist, 'psfdx-logo.png')).equals(original));
  assert.equal(fs.existsSync(path.join(here, 'src', 'psfdx-logo.png')), false, 'do not keep a second copy of the logo in site/src');
});

test('no placeholder is left in any built file', () => {
  const walk = dir => fs.readdirSync(dir).flatMap(n => { const p = path.join(dir, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; });
  for (const file of walk(dist)) {
    if (/\.(png|woff2)$/.test(file)) continue;
    assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /%[A-Z_]+(_URL|_VERSION)%/, path.relative(dist, file));
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

test('every local file the page and stylesheet refer to exists in the build', () => {
  const refs = [...html.matchAll(/(?:href|src)="(\/[^"#?]*)"/g)].map(m => m[1]).filter(r => r !== '/');
  assert.ok(refs.length >= 5);
  for (const ref of refs) assert.ok(fs.existsSync(path.join(dist, ref)), `${ref} is missing from the build`);
  for (const m of css.matchAll(/url\((\/[^)]+)\)/g)) assert.ok(fs.existsSync(path.join(dist, m[1])), `${m[1]} (from the stylesheet) is missing`);
  assert.ok(fs.existsSync(path.join(dist, 'og-image.png')));
  assert.ok(fs.existsSync(path.join(dist, '_headers')));
});

test('the sections are present, in order', () => {
  const marks = ['class="site-header"', 'class="hero"', 'class="marquee-band"', 'id="why"', 'id="get-started"', 'id="modules"', 'class="closing"', 'class="site-footer"'];
  let last = -1;
  for (const mark of marks) {
    const at = html.indexOf(mark);
    assert.ok(at > last, `${mark} is missing or out of order`);
    last = at;
  }
  assert.ok(html.indexOf('id="console"') > html.indexOf('class="hero"') && html.indexOf('id="console"') < html.indexOf('class="marquee-band"'), 'the console sits in the hero');
});

test('the header links work: Modules, Releases and the GitHub pill', () => {
  const nav = html.match(/<nav aria-label="Main">[\s\S]*?<\/nav>/)[0];
  assert.match(nav, /href="\/modules\/">Modules</);
  assert.match(nav, /href="https:\/\/github\.com\/tonygward\/psfdx\/releases">Releases</);
  assert.match(nav, /class="nav-cta" href="https:\/\/github\.com\/tonygward\/psfdx">/);
  assert.match(nav, /GitHub/);
});

test('the hero: headline, tagline, copy command, docs link and release pill', () => {
  const h1 = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/)[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  assert.equal(h1, 'Salesforce. Meet PowerShell.');
  assert.match(html, /<span class="y">Meet<\/span> <span class="b">PowerShell\.<\/span>/);
  assert.ok(html.includes('Powerful Salesforce tools.<br>Familiar PowerShell commands.<br>One <span class="pipe">|</span> away from anything.'));
  assert.match(html, /class="install" data-copy="Install-Module psfdx"/);
  assert.match(html, /<code>Install-Module psfdx<\/code>/);
  assert.match(html, /class="button secondary" href="\/modules\/">Read the docs</);
});

test('the release pill shows the version in the VERSION file, never a typed-in number', () => {
  assert.match(html, new RegExp(`>v${release.replace(/\./g, '\\.')} — latest release<`));
  assert.match(html, /class="release-pill" href="https:\/\/github\.com\/tonygward\/psfdx\/releases"/);
  const source = fs.readFileSync(path.join(here, 'src', 'index.html'), 'utf8');
  assert.doesNotMatch(source, /\b\d+\.\d+\.\d+\b/, 'the source holds only the %RELEASE_VERSION% placeholder');
  assert.match(source, /v%RELEASE_VERSION%/);
});

test('the console shows the sample session, marked as made-up data', () => {
  for (const text of ['Connect-Salesforce</span> <span class="param">-Sandbox</span>', 'Select-SalesforceRecords</span> <span class="param">-Query</span> <span class="str">"SELECT Id, Name FROM Account LIMIT 4"</span>', 'pwsh — psfdx', 'Sample session with made-up data. It is not a live org.']) {
    assert.ok(html.includes(text), text);
  }
  assert.equal((html.match(/class="line"><span class="prompt">PS&gt;<\/span>|class="line">0{2}1xx/g) || []).length >= 4, true);
  assert.match(html, /class="dot dot-r"/);
  for (const colour of ['.prompt', '.cmd', '.param', '.str']) assert.ok(css.includes(colour), `${colour} syntax colour`);
});

test('the marquee lists real psfdx commands (and Export-Csv), twice, with the copy hidden from screen readers', () => {
  const lists = [...html.matchAll(/<ul class="marquee-track[^"]*"[^>]*>([\s\S]*?)<\/ul>/g)];
  assert.equal(lists.length, 2);
  assert.match(lists[1][0], /aria-hidden="true"/);
  const names = [...lists[0][1].matchAll(/<li>([^<]+)<\/li>/g)].map(m => m[1]);
  assert.deepEqual(names, ['Connect-Salesforce', 'Select-SalesforceRecords', 'Upsert-SalesforceRecord', 'Test-SalesforceFlow', 'Test-SalesforceApex', 'Get-SalesforceAlias', 'Update-SalesforceCli', 'Export-Csv']);
  assert.deepEqual([...lists[1][1].matchAll(/<li>([^<]+)<\/li>/g)].map(m => m[1]), names);
  for (const name of names.filter(n => n !== 'Export-Csv')) assert.ok(exported.has(name), `${name} is not exported by any psfdx module`);
  assert.match(css, /@keyframes marquee \{ from \{ transform: translateX\(0\); \} to \{ transform: translateX\(-50%\); \} \}/);
  assert.match(css, /animation: marquee 32s linear infinite/);
});

test('the feature tiles and all ten public modules use real content', () => {
  for (const text of ['| pipeline', 'Objects, not JSON', 'win · mac · linux', 'Runs everywhere', 'Get-Command · Get-Help', 'Everything is discoverable', 'save · deploy · test', 'Deploy and test as you save', 'A simpler, more intuitive way to work with Salesforce.', 'One install.', 'Every Salesforce workflow.', "Get-Command -Module 'psfdx*'"]) {
    assert.ok(html.includes(text), text);
  }
  const modules = [...modulesPage.matchAll(/class="module-name">([^<]+)</g)].map(m => m[1]);
  assert.deepEqual(modules, ['psfdx', 'psfdx-data', 'psfdx-org', 'psfdx-metadata', 'psfdx-logs', 'psfdx-development', 'psfdx-devops', 'psfdx-packages', 'psfdx-agentforce', 'psfdx-plugins']);
  for (const m of modules) assert.ok(fs.existsSync(path.join(repoRoot, m, `${m}.psd1`)), `${m} is not a module in this repository`);
  for (const m of modules) assert.ok(modulesPage.includes(`href="/modules/${m}/"`), `missing module documentation link ${m}`);
});

test('the homepage copy is tight: four feature tiles including Watch, Get started below them, and a link to the modules', () => {
  assert.ok(!html.includes('Less time remembering CLI syntax'), 'the repeated tagline is gone');
  assert.ok(!html.includes('See exactly what runs') && !html.includes('Get-SalesforceOrgDetails -TargetOrg dev -Verbose'), 'the -Verbose card is replaced');
  assert.match(html, /Every command returns real PowerShell objects, not text to parse[\s\S]*No <code>jq<\/code>, no string handling/);
  assert.match(html, /<h3>Everything is discoverable<\/h3>[\s\S]*Get-Command -Module 'psfdx\*'[\s\S]*Get-Help Deploy-SalesforceMetadata -Examples/);
  for (const gone of ['BUILT FOR POWERSHELL', 'The little things that make a big difference', 'Compare the PowerShell and Bash examples', 'Explore each module above', 'Every command explained', 'One update, every module']) assert.ok(!html.includes(gone), gone);
  assert.ok(!/update-tile/.test(html + css), 'the old update tile is gone');
  assert.ok(!/Copy the install command/.test(fs.readFileSync(new URL('./src/script.js', import.meta.url), 'utf8')), 'copy label is not install-specific');
  assert.ok(!/\.disclaimer \{[^}]*max-width/.test(css), 'the disclaimer is not narrowed');
  for (const [, id] of html.matchAll(/href="#([^"]+)"/g)) assert.ok(html.includes('id="' + id + '"'), 'dead in-page anchor #' + id);
  const levels = [...html.matchAll(/<h([1-6])[ >]/g)].map(m => Number(m[1]));
  for (let i = 1; i < levels.length; i++) assert.ok(levels[i] - levels[i - 1] <= 1, 'heading levels skip near heading ' + (i + 1));
});

// Issue 308: a simpler homepage, with the module catalogue on its own page.
test('the homepage has no export comparison and no standalone Watch section', () => {
  for (const gone of ['id="powershell-examples"', 'Comparison: Export accounts to CSV', 'Bash with the Salesforce CLI and jq', 'id="watch"', 'class="module-list"', 'class="module-row"']) assert.ok(!html.includes(gone), gone);
  for (const gone of ['.pipeline-comparison', '.watch-example', '#powershell-examples']) assert.ok(!css.includes(gone), `unused rule ${gone}`);
});

test('the four feature tiles share one style, the last one is Watch, and they reflow on small screens', () => {
  const cards = html.match(/<ul class="cards">([\s\S]*?)<\/ul>/)[1];
  const tiles = [...cards.matchAll(/<li class="card">([\s\S]*?)<\/li>/g)].map(m => m[1]);
  assert.equal(tiles.length, 4);
  for (const tile of tiles) assert.match(tile, /^\s*<p class="card-tag">[^<]+<\/p>\s*<h3>[^<]+<\/h3>\s*<p>/, 'tag, heading and copy');
  assert.match(tiles[3], /<h3>Deploy and test as you save<\/h3>/);
  assert.match(tiles[3], /href="\/modules\/psfdx-development\/#Watch-SalesforceApex"><code>Watch-SalesforceApex<\/code><\/a>/);
  const textLength = tile => tile.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim().length;
  assert.ok(textLength(tiles[3]) <= Math.max(...tiles.slice(0, 3).map(textLength)), 'the Watch tile is no longer than the others');
  assert.match(css, /#why \.cards \{ grid-template-columns: repeat\(4, minmax\(0, 1fr\)\); \}/);
  assert.match(css, /@media \(max-width: 1100px\) \{ #why \.cards \{ grid-template-columns: repeat\(2, minmax\(0, 1fr\)\); \} \}/);
  assert.match(css, /@media \(max-width: 640px\) \{ #why \.cards \{ grid-template-columns: minmax\(0, 1fr\); \} \}/);
});

test('Get started sits directly below the tiles on the homepage and is not repeated on the psfdx page', () => {
  assert.match(html, /<\/ul>\s*<\/div>\s*<\/section>\s*<section id="get-started" class="section" aria-labelledby="get-started-title">/, 'directly after the tiles');
  const section = html.match(/<section id="get-started"[\s\S]*?<\/section>/)[0];
  assert.match(section, /<h2 id="get-started-title">Get started<\/h2>/);
  assert.match(section, /data-copy="Install-Module psfdx&#10;Import-Module psfdx&#10;Get-Command -Module psfdx"/);
  assert.ok(section.includes('There is only one PowerShell Gallery package: <code>psfdx</code>.'));
  assert.ok(section.includes('href="https://github.com/tonygward/psfdx/blob/main/docs/install.md"'));
  const core = fs.readFileSync(path.join(dist, 'modules', 'psfdx', 'index.html'), 'utf8');
  assert.ok(!core.includes('id="get-started"') && !core.includes('Get started</h2>'), 'no second Get started section');
  assert.ok(core.includes('href="/#get-started"'), 'the psfdx page points to it');
});

test('the Modules page lists every module and is linked from the homepage, the navigation and every module page', () => {
  assert.match(modulesPage, /<h1 id="modules-title">/);
  assert.equal((modulesPage.match(/<h1[ >]/g) || []).length, 1);
  assert.match(modulesPage, /<link rel="canonical" href="https:\/\/psfdx\.com\/modules\/">/);
  assert.match(modulesPage, /<nav aria-label="Main">[\s\S]*href="\/modules\/">Modules<[\s\S]*<\/nav>/);
  assert.match(modulesPage, /<\/ul>\s*<div class="update-row">\s*<div class="install" data-copy="Update-Module psfdx">[\s\S]*?<code>Update-Module psfdx<\/code><\/div>\s*<p>One command updates every module\.<\/p>/);
  assert.ok(modulesPage.includes('<script src="/script.js" defer></script>'), 'the copy button works');
  assert.ok(modulesPage.includes('psfdx is an independent open-source project and is not affiliated with or endorsed by Salesforce.'));
  for (const ref of [...modulesPage.matchAll(/(?:href|src)="(\/[^"#?]*)"/g)].map(m => m[1]).filter(r => r !== '/')) {
    assert.ok(fs.existsSync(path.join(dist, ref.endsWith('/') ? ref + 'index.html' : ref)), `${ref} is missing from the build`);
  }
  assert.match(html, /<section id="modules"[\s\S]*?class="button secondary" href="\/modules\/">Browse all modules →<\/a>/, 'a prominent homepage link');
  for (const dir of fs.readdirSync(path.join(dist, 'modules'), { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name)) {
    const page = fs.readFileSync(path.join(dist, 'modules', dir, 'index.html'), 'utf8');
    assert.ok(page.includes('href="/modules/">Modules</a>'), `${dir}: Modules in the navigation`);
    assert.ok(!page.includes('href="/#modules"'), `${dir}: links to the Modules page, not the homepage`);
  }
  assert.match(css, /\.nav-list a:not\(\.nav-cta\):not\(\[href="\/modules\/"\]\) \{ display: none; \}/, 'Modules stays in the navigation on phones');
  const sitemap = fs.readFileSync(path.join(dist, 'sitemap.xml'), 'utf8');
  assert.match(sitemap, /<loc>https:\/\/psfdx\.com\/modules\/<\/loc>/);
  assert.doesNotMatch(sitemap, /index\.html/);
});

test('the website highlights built-in help, suite updates and native CSV pipelines', () => {
  for (const command of ['Get-Help Deploy-SalesforceMetadata -Examples', 'Select-SalesforceRecords', 'Export-Csv']) assert.ok(html.includes(command), command);
  assert.ok(fs.readFileSync(path.join(dist, 'modules', 'psfdx', 'index.html'), 'utf8').includes("Export-Csv -Path './accounts.csv' -NoTypeInformation"), 'the CSV example is on the psfdx page');
  for (const m of ['psfdx', 'psfdx-metadata', 'psfdx-devops', 'psfdx-data', 'psfdx-plugins', 'psfdx-development', 'psfdx-logs', 'psfdx-org', 'psfdx-packages', 'psfdx-agentforce']) {
    const doc = path.join(dist, 'modules', m, 'index.html');
    assert.ok(fs.existsSync(doc), `documentation missing: ${m}`);
    assert.ok(fs.readFileSync(doc, 'utf8').includes('Get-Command -Module ' + m), `commands missing: ${m}`);
  }
});

test('the closing panel and footer', () => {
  assert.ok(html.includes('PowerShell simplicity. Salesforce capability.'));
  assert.match(html, /data-copy="Install-Module psfdx&#10;Import-Module psfdx&#10;Connect-Salesforce -Sandbox"/);
  assert.ok(html.includes('psfdx · <a href="https://github.com/tonygward/psfdx/blob/main/LICENSE">MIT licence</a>'));
  assert.ok(html.includes('psfdx is an independent open-source project and is not affiliated with or endorsed by Salesforce.'));
  assert.match(html, /<title>psfdx/);
  assert.match(html, /<meta name="description"/);
});

test('the palette and type come from the design', () => {
  for (const hex of ['#010F2B', '#012456', '#0A2150', '#0B1F44', '#FFE14D', '#4D9BFF', '#61D6D6', '#7BE38A', '#F2F4FA', '#C9D3EA', '#1D3C78', '#2A4D8F']) {
    assert.ok(css.toLowerCase().includes(hex.toLowerCase()), hex);
  }
  assert.match(css, /max-width: 1240px/);
  assert.match(css, /clamp\(20px, 4vw, 48px\)/);
  assert.match(css, /font-family: 'Bricolage Grotesque'/);
  assert.match(css, /font-family: 'IBM Plex Mono'/);
  assert.match(css, /rotate\(-1\.5deg\)/);
  assert.match(css, /translateY\(-10px\)/);
  assert.match(css, /animation: float 6s ease-in-out infinite/);
});

test('fonts are self-hosted, so the page makes no outside requests', () => {
  for (const f of ['BricolageGrotesque-latin.woff2', 'IBMPlexMono-400.woff2', 'IBMPlexMono-500.woff2', 'IBMPlexMono-600.woff2']) {
    const file = path.join(dist, 'fonts', f);
    assert.ok(fs.existsSync(file), f);
    assert.equal(fs.readFileSync(file).subarray(0, 4).toString('latin1'), 'wOF2', `${f} is a woff2 file`);
  }
  assert.doesNotMatch(css, /fonts\.googleapis|fonts\.gstatic/);
  assert.doesNotMatch(html, /fonts\.googleapis|fonts\.gstatic/);
});

test('accessibility basics: language, one h1, skip link, alt text, labelled landmarks, focus and reduced motion', () => {
  assert.match(html, /<html lang="en-GB"/);
  assert.equal((html.match(/<h1[ >]/g) || []).length, 1);
  assert.match(html, /class="skip-link" href="#main"/);
  assert.match(html, /<main id="main">/);
  for (const img of html.match(/<img\b[^>]*>/g)) assert.match(img, /\balt="[^"]+"/, img);
  assert.match(css, /:focus-visible/);
  assert.match(html, /class="console-body" aria-hidden="true"/);
  assert.match(html, /<p class="sr-only">Example PowerShell session\./, 'the animated console has a text alternative');
});

test('reduced motion turns off the typing, float and marquee and shows everything', () => {
  const block = css.slice(css.indexOf('@media (prefers-reduced-motion: reduce)'));
  assert.match(block, /\.console \{ animation: none; \}/);
  assert.match(block, /\.marquee \{ animation: none;/);
  assert.match(block, /\.marquee-dup \{ display: none; \}/);
  assert.match(block, /\.js-anim \.results \{ opacity: 1;/);
  assert.match(js, /prefers-reduced-motion: reduce/);
  assert.match(js, /if \(!consoleEl \|\| reduceMotion\) \{ return; \}/, 'the script never starts the typing when motion is reduced');
});

test('the page does not scroll sideways', () => {
  assert.match(css, /body \{[^}]*overflow-x: clip/);
  assert.match(css, /\.marquee-band \{[^}]*overflow: hidden/);
  assert.match(css, /@media \(max-width: 900px\)/);
  assert.match(css, /@media \(max-width: 640px\)/);
});

test('copy to the clipboard: exact text, COPY then COPIED for 1.6 seconds, and a failure path', () => {
  assert.match(js, /'COPIED'/);
  assert.match(js, /1600/);
  assert.match(js, /'COPY'/);
  assert.match(js, /PRESS CTRL\+C/);
  assert.match(js, /navigator\.clipboard\.writeText/);
  assert.match(js, /execCommand\('copy'\)/, 'a fallback where the clipboard API is missing');
  assert.match(js, /keydown/, 'keyboard users can copy too');
  assert.doesNotMatch(html, /Install-Module psfdx\s*[^<&"\s]/ , 'the command is exactly Install-Module psfdx');
});

test('the console typing follows the specified timings', () => {
  assert.match(js, /CHAR_MS = 55/);
  assert.match(js, /FADE_MS = 250/);
  assert.match(js, /HOLD_MS = 3300/);
  assert.match(css, /\.js-anim \.results \{ opacity: 0; transition: opacity \.25s ease; \}/);
  assert.match(css, /\.cursor \{[^}]*animation: blink/);
});

test('the page makes no outside requests and uses no inline script or style', () => {
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)/);
  assert.doesNotMatch(html, /\sstyle=/);
  assert.doesNotMatch(css, /url\(\s*['"]?https?:/);
  for (const m of html.matchAll(/<(?:script|link|img)\b[^>]*(?:src|href)="(https?:[^"]+)"/g)) {
    assert.match(m[0], /<link rel="canonical"|<link[^>]*og/, `outside resource: ${m[1]}`);
  }
});

test('the content security policy allows only the site itself, including its fonts', () => {
  const headers = fs.readFileSync(path.join(dist, '_headers'), 'utf8');
  assert.match(headers, /Content-Security-Policy: default-src 'self'/);
  assert.match(headers, /font-src 'self'/);
  assert.doesNotMatch(headers, /unsafe-inline|unsafe-eval|https?:\/\//);
});

test('claims stay accurate: only the build-time release number, and no Salesforce endorsement wording', () => {
  const numbers = html.match(/\b\d+\.\d+\.\d+\b/g) || [];
  for (const n of numbers) assert.equal(n, release, 'the only version on the page is the current release');
  assert.doesNotMatch(html, /official partner|certified by|endorsed by Salesforce\.(?!<)/i);
});

test('applyConfig replaces every occurrence', () => {
  assert.equal(applyConfig('%GITHUB_URL% %GITHUB_URL% v%RELEASE_VERSION%', readConfig({})), `https://github.com/tonygward/psfdx https://github.com/tonygward/psfdx v${release}`);
});


test('module pages display PowerShell prompts, compact code blocks and ordered core examples', () => {
  const moduleNames = ['psfdx', 'psfdx-metadata', 'psfdx-devops', 'psfdx-data', 'psfdx-plugins', 'psfdx-development', 'psfdx-logs', 'psfdx-org', 'psfdx-packages', 'psfdx-agentforce'];
  for (const name of moduleNames) {
    const page = fs.readFileSync(path.join(dist, 'modules', name, 'index.html'), 'utf8');
    assert.match(page, /class="ps-prompt">PS&gt;<\/span>/, name + ' should display PS prompt');
    assert.match(page, /class="code-box terminal-example"/, name + ' should use styled terminal');
  }
  const core = fs.readFileSync(path.join(dist, 'modules', 'psfdx', 'index.html'), 'utf8');
  const snippets = ['1. Connect to your sandbox', '2. Explore built-in help', '3. Export Salesforce records to CSV', '4. Update the entire suite'];
  let previous = -1;
  for (const snippet of snippets) {
    const position = core.indexOf(snippet);
    assert.ok(position > previous, snippet + ' must follow preceding example');
    previous = position;
  }
  assert.match(core, /<span class="terminal-output">NAME/, 'help contains a sample result');
  assert.match(core, /Illustrative excerpt, shortened for readability/, 'sample result is clearly labelled');
  assert.match(core, /Update-Module psfdx<\/span><\/code><\/pre><\/div>/, 'update is last executable example');
  for (const rule of ['.documentation h2', '.documentation .ps-prompt', '.documentation .terminal-output', '.documentation .terminal-continuation']) {
    assert.ok(css.includes(rule), rule);
  }
});


// ---- the command reference on the module pages (generated by site/Update-ModuleReference.ps1) ----
const allModuleDirs = fs.readdirSync(repoRoot).filter(d => /^psfdx/.test(d) && fs.existsSync(path.join(repoRoot, d, `${d}.psd1`)));
// Internal modules export no commands: they are not part of the public surface, so they have no page, no homepage row and no reference.
const moduleDirs = allModuleDirs.filter(d => exportsOf(d).length > 0);
function exportsOf(dir) {
  const manifest = fs.readFileSync(path.join(repoRoot, dir, `${dir}.psd1`), 'utf8');
  const block = manifest.match(/FunctionsToExport\s*=\s*@\(([\s\S]*?)\)/);
  return [...(block ? block[1] : '').matchAll(/'([^']+)'/g)].map(m => m[1]);
}
const pageOf = dir => fs.readFileSync(path.join(dist, 'modules', dir, 'index.html'), 'utf8');

test('every exported command of every module is documented once, under its owning module', () => {
  assert.ok(moduleDirs.length >= 10, 'all the public modules');
  const seen = new Map();
  for (const dir of moduleDirs) {
    const page = pageOf(dir);
    const names = exportsOf(dir);
    assert.ok(names.length > 0, dir);
    const ids = [...page.matchAll(/<details class="cmd" id="([^"]+)">/g)].map(m => m[1]);
    assert.deepEqual([...ids].sort(), [...names].sort(), `${dir}: the entries are exactly the exported commands`);
    const alphabetical = commands => [...commands].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
    assert.doesNotMatch(page, /class="cmd-index"/, `${dir}: no duplicate index`);
    const groups = [...page.matchAll(/<section class="cmd-group">\s*<h3>([^<]+)<\/h3>([\s\S]*?)<\/section>/g)];
    if (names.length >= 20 || dir === 'psfdx-org') {
      assert.ok(groups.length > 1, `${dir}: command types`);
      const groupedIds = groups.flatMap(([, type, contents]) => {
        const commands = [...contents.matchAll(/<details class="cmd" id="([^"]+)">/g)].map(match => match[1]);
        assert.ok(commands.length, `${dir}: ${type}`);
        assert.deepEqual(commands, alphabetical(commands), `${dir}: ${type} is alphabetical`);
        return commands;
      });
      assert.deepEqual(groupedIds, ids, dir);
    } else {
      assert.equal(groups.length, 0, dir);
      assert.deepEqual(ids, alphabetical(ids), dir);
    }
    for (const id of ids) { assert.equal(seen.has(id), false, `${id} is documented on ${seen.get(id)} and on ${dir}`); seen.set(id, dir); }
  }
  assert.equal(seen.size, exported.size, 'every exported command of the suite is documented');
});

test('commands with different verbs share the same command type', () => {
  for (const [module, type, commands] of [
    ['psfdx-devops', 'Pipelines and stages', ['Add-SalesforceDevOpsPipelineStage', 'Get-SalesforceDevOpsPipeline', 'Update-SalesforceDevOpsPipeline']],
    ['psfdx-metadata', 'Deployments', ['Deploy-SalesforceMetadata', 'Get-SalesforceDeployStatus', 'Stop-SalesforceDeploy']],
  ]) {
    const group = [...pageOf(module).matchAll(/<section class="cmd-group">\s*<h3>([^<]+)<\/h3>([\s\S]*?)<\/section>/g)].find(match => match[1] === type);
    assert.ok(group, type);
    for (const command of commands) assert.ok(group[2].includes(`id="${command}"`), command);
  }
  assert.match(css, /\.cmd-description\s*\{\s*color:\s*var\(--text\)/);
});

test('psfdx-org lists its sandbox and scratch org commands together, grouped by Sandboxes and Scratch Orgs', () => {
  const page = pageOf('psfdx-org');
  const groups = new Map([...page.matchAll(/<section class="cmd-group">\s*<h3>([^<]+)<\/h3>([\s\S]*?)<\/section>/g)].map(([, name, body]) => [name, [...body.matchAll(/<details class="cmd" id="([^"]+)">/g)].map(m => m[1])]));
  assert.deepEqual([...groups.keys()], ['Sandboxes', 'Scratch Orgs']);
  assert.ok(groups.get('Sandboxes').length >= 7 && groups.get('Sandboxes').every(n => /Sandbox/.test(n)));
  assert.deepEqual(groups.get('Scratch Orgs'), ['Get-SalesforceScratchOrgs', 'New-SalesforceScratchOrg', 'Remove-SalesforceScratchOrg', 'Remove-SalesforceScratchOrgs', 'Resume-SalesforceScratchOrg']);
  assert.equal(pageOf('psfdx-development').includes('id="New-SalesforceScratchOrg"'), false, 'the scratch org commands left psfdx-development');
  assert.equal(fs.existsSync(path.join(dist, 'modules', 'psfdx-sandbox')), false, 'the retired module has no page');
});

test('every entry has a description, syntax and a practical example with the PS> prompt', () => {
  for (const dir of moduleDirs) {
    const page = pageOf(dir);
    for (const m of page.matchAll(/<details class="cmd" id="([^"]+)">([\s\S]*?)<\/details>/g)) {
      const [, name, body] = m;
      assert.ok(body.startsWith(`<summary><span class="cmd-name">${name}</span></summary>`), `${name}: collapsed label`);
      assert.match(body, /<h4>Description<\/h4><p class="cmd-description">[^<]+<\/p>/, `${name}: description`);
      assert.match(body, /<h4>Syntax<\/h4><pre class="cmd-syntax"><code>/, `${name}: syntax`);
      assert.match(body, /<h4>Examples<\/h4>/, `${name}: example`);
      assert.match(body, /class="ps-prompt">PS&gt;<\/span>/, `${name}: PS> prompt`);
    }
  }
});

// Issue 306: every command reference, on the website and in the GitHub Markdown, has the same sections in the same order.
const sectionOrder = ['Synopsis', 'Syntax', 'Description', 'Parameters', 'Salesforce CLI', 'Examples', 'Remarks', 'Related Links'];
const expectedSections = hasParameters => sectionOrder.filter(s => hasParameters || s !== 'Parameters');

test('every website entry has the standard sections in the standard order, with no NAME, Inputs or Outputs', () => {
  for (const dir of moduleDirs) {
    for (const m of pageOf(dir).matchAll(/<details class="cmd" id="([^"]+)">([\s\S]*?)<\/details>/g)) {
      const [, name, body] = m;
      const headings = [...body.matchAll(/<h4>([^<]+)<\/h4>/g)].map(h => h[1]);
      assert.deepEqual(headings, expectedSections(body.includes('<dl class="cmd-params">')), `${dir}/${name}`);
      assert.ok(!headings.some(h => /^(name|inputs|outputs)$/i.test(h)), `${name}: no NAME, Inputs or Outputs`);
    }
  }
});

test('the GitHub Markdown reference has the same commands and the same section order as the website', () => {
  const folder = path.join(repoRoot, 'docs', 'reference');
  const index = fs.readFileSync(path.join(folder, 'README.md'), 'utf8');
  for (const dir of moduleDirs) {
    assert.ok(index.includes(`[${dir}](${dir}.md)`), `${dir}: linked from the index`);
    const text = fs.readFileSync(path.join(folder, `${dir}.md`), 'utf8').replace(/\r\n/g, '\n');
    const entries = [...text.matchAll(/^### (\S+)\n([\s\S]*?)(?=^### |^## |$(?![\s\S]))/gm)];
    assert.deepEqual(entries.map(e => e[1]), [...pageOf(dir).matchAll(/<details class="cmd" id="([^"]+)">/g)].map(m => m[1]), `${dir}: same commands in the same order`);
    for (const [, name, body] of entries) {
      const headings = [...body.matchAll(/^#### (.+)$/gm)].map(h => h[1]);
      assert.deepEqual(headings, expectedSections(headings.includes('Parameters')), `${dir}/${name}`);
      assert.ok(!headings.some(h => /^(name|inputs|outputs)$/i.test(h)), `${name}: no NAME, Inputs or Outputs`);
    }
  }
  assert.ok(!/internal/i.test('') && !fs.existsSync(path.join(folder, 'psfdx-shared.md')), 'no Markdown reference for the internal module');
});

test('module pages other than the main one are a brief introduction and a command reference, and link to the main installation instructions', () => {
  for (const dir of moduleDirs.filter(d => d !== 'psfdx')) {
    const page = pageOf(dir);
    const intro = page.slice(page.indexOf('<main'), page.indexOf('id="reference"'));
    assert.ok(intro.length < 2200, `${dir}: the introduction before the reference is brief (${intro.length} characters)`);
    assert.ok(!/Install-Module|Update-Module|Get started|<h2>Examples<\/h2>/.test(page.replace(/<details class="cmd"[\s\S]*?<\/details>/g, '')), `${dir}: no installation or marketing copy outside the reference`);
    assert.ok(page.includes('href="/#get-started"'), `${dir}: links to the installation instructions`);
    assert.ok(page.includes('Get-Command -Module ' + dir), `${dir}: shows how to list its commands`);
    assert.match(page, /<h1>psfdx[-a-z]*<\/h1><p class="tagline">[^<]+<\/p><p class="section-intro">[^<]+/, `${dir}: keeps its definition and overview`);
  }
});

test('the main psfdx page keeps its introduction and examples, and has the reference of its own commands at the bottom', () => {
  const page = pageOf('psfdx');
  for (const text of ['Core commands', '1. Connect to your sandbox', '2. Explore built-in help', '3. Export Salesforce records to CSV', '4. Update the entire suite']) assert.ok(page.includes(text), text);
  const reference = page.indexOf('id="reference"');
  assert.ok(reference > page.indexOf('4. Update the entire suite'), 'the reference comes after the existing examples');
  assert.ok(page.indexOf('<details class="cmd"') > reference, 'the entries are in the reference');
  assert.equal([...page.matchAll(/<details class="cmd"/g)].length, exportsOf('psfdx').length, 'only its own commands');
});

test('the reference pages load their small script and work without it', () => {
  assert.ok(fs.existsSync(path.join(dist, 'reference.js')));
  const script = fs.readFileSync(path.join(dist, 'reference.js'), 'utf8');
  assert.ok(!/https?:\/\//.test(script), 'no outside requests');
  for (const dir of moduleDirs) assert.ok(pageOf(dir).includes('<script src="/reference.js" defer></script>'), dir);
  for (const rule of ['details.cmd', '.cmd-group', '.cmd-params', '.cmd-syntax']) assert.ok(css.includes(rule), rule);
});


test('internal modules are not on the public website, and the public commands that moved to core are in its reference', () => {
  const internal = allModuleDirs.filter(d => exportsOf(d).length === 0);
  assert.deepEqual(internal, ['psfdx-shared'], 'only psfdx-shared is internal');
  for (const dir of internal) {
    assert.equal(fs.existsSync(path.join(dist, 'modules', dir)), false, `${dir}: no page`);
    assert.equal(html.includes(dir), false, `${dir}: not on the homepage`);
    assert.equal(fs.readFileSync(path.join(dist, 'sitemap.xml'), 'utf8').includes(dir), false, `${dir}: not in the sitemap`);
    for (const page of moduleDirs) assert.equal(pageOf(page).includes(`/modules/${dir}/`), false, `${page}: no link to ${dir}`);
  }
  const core = pageOf('psfdx');
  for (const name of ['ConvertTo-SalesforceSoqlLiteral', 'ConvertTo-SalesforceSoqlIdentifier', 'ConvertTo-SalesforceSoqlDateTime']) {
    assert.ok(exportsOf('psfdx').includes(name), `${name} is exported by core`);
    assert.ok(core.includes(`id="${name}"`), `${name} is in the core reference`);
  }
  for (const name of ['Invoke-Salesforce', 'Show-SalesforceResult', 'Get-PsfdxCommonParameterSplat']) {
    for (const dir of moduleDirs) assert.equal(pageOf(dir).includes(`id="${name}"`), false, `${name} is internal, so it is on no page`);
  }
});

test('cleanup', () => { fs.rmSync(out, { recursive: true, force: true }); });
