// The command reference of the module pages, built from the PowerShell source of every module. No dependencies; needs Node 18 or later.
//
// It reads the comment-based help and the parameter block of every command a module exports (the text Get-Help reads) and renders, for each module,
// an alphabetical linked index and one compact expandable entry per command: synopsis, syntax (one line per parameter set), parameters, a practical
// example with the PS> prompt, and the Salesforce CLI command it runs. build.mjs puts the result into the page of the module between
// <!-- reference:start --> and <!-- reference:end -->, so the website is always built from the current source and nothing generated is committed.
// site/ModuleReference.Tests.ps1 compares what this reads with what Get-Help says for every command.
//
//   node site/reference.mjs --json        print the data (used by the tests)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(here, '..');

export const START = '<!-- reference:start -->';
export const END = '<!-- reference:end -->';

export function escapeHtml(text) {
  return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// ---- reading PowerShell source ----------------------------------------------------------------------------------------------------------

// Returns the index just after the string or comment that starts at i, or i itself when none starts there.
function skipStringOrComment(s, i) {
  const c = s[i];
  if (c === "'") {
    let j = i + 1;
    while (j < s.length) { if (s[j] === "'") { if (s[j + 1] === "'") { j += 2; continue; } return j + 1; } j++; }
    return s.length;
  }
  if (c === '"') {
    let j = i + 1;
    while (j < s.length) { if (s[j] === '`') { j += 2; continue; } if (s[j] === '"') { if (s[j + 1] === '"') { j += 2; continue; } return j + 1; } j++; }
    return s.length;
  }
  if (c === '<' && s[i + 1] === '#') { const e = s.indexOf('#>', i + 2); return e < 0 ? s.length : e + 2; }
  if (c === '#') { const e = s.indexOf('\n', i); return e < 0 ? s.length : e; }
  return i;
}

// The text between the bracket at `open` and its matching close, and the index after the close.
function balanced(s, open, openChar, closeChar) {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const skipped = skipStringOrComment(s, i);
    if (skipped !== i) { i = skipped - 1; continue; }
    if (s[i] === openChar) depth++;
    else if (s[i] === closeChar) { depth--; if (depth === 0) return { inner: s.slice(open + 1, i), end: i + 1 }; }
  }
  throw new Error(`unbalanced ${openChar}`);
}

function splitTopLevel(text, separator) {
  const parts = []; let depth = 0; let start = 0;
  for (let i = 0; i < text.length; i++) {
    const skipped = skipStringOrComment(text, i);
    if (skipped !== i) { i = skipped - 1; continue; }
    const c = text[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === separator && depth === 0) { parts.push(text.slice(start, i)); start = i + 1; }
  }
  parts.push(text.slice(start));
  return parts;
}

// The functions of a source file with the help comment and the parameter block each one starts with.
export function parseFunctions(source) {
  const text = source.replace(/\r\n/g, '\n');
  const found = new Map();
  const pattern = /^function\s+([A-Za-z][A-Za-z0-9-]*)\s*\{/gm;
  let m;
  while ((m = pattern.exec(text)) !== null) {
    const name = m[1];
    let i = m.index + m[0].length;
    let help = null;
    let params = '';
    // walk the start of the body: the help comment, attributes, then Param( ... )
    while (i < text.length) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('<#', i)) {
        const end = text.indexOf('#>', i + 2);
        const block = text.slice(i + 2, end);
        if (help === null && /^\s*\.SYNOPSIS/im.test(block)) help = block;
        i = end + 2; continue;
      }
      if (text[i] === '#') { i = skipStringOrComment(text, i); continue; }
      if (text[i] === '[') { i = balanced(text, i, '[', ']').end; continue; }
      if (/^param\s*\(/i.test(text.slice(i, i + 12))) { const open = text.indexOf('(', i); params = balanced(text, open, '(', ')').inner; break; }
      break;
    }
    found.set(name, { help, params });
  }
  return found;
}

export function parseHelp(block) {
  const sections = [];
  let current = null;
  for (const line of (block || '').split('\n')) {
    const key = line.match(/^\s*\.([A-Za-z]+)\s*(.*)$/);
    if (key && ['SYNOPSIS', 'DESCRIPTION', 'PARAMETER', 'EXAMPLE', 'NOTES', 'LINK', 'INPUTS', 'OUTPUTS', 'COMPONENT', 'ROLE', 'FUNCTIONALITY', 'FORWARDHELPTARGETNAME', 'FORWARDHELPCATEGORY', 'REMOTEHELPRUNSPACE', 'EXTERNALHELP'].includes(key[1].toUpperCase())) {
      current = { key: key[1].toUpperCase(), arg: key[2].trim(), lines: [] };
      sections.push(current);
    } else if (current) current.lines.push(line);
  }
  const text = s => s.lines.join('\n').trim();
  return {
    synopsis: (sections.find(s => s.key === 'SYNOPSIS') ? text(sections.find(s => s.key === 'SYNOPSIS')) : '').replace(/\s+/g, ' '),
    parameters: new Map(sections.filter(s => s.key === 'PARAMETER').map(s => [s.arg.toLowerCase(), text(s).replace(/\s+/g, ' ')])),
    examples: sections.filter(s => s.key === 'EXAMPLE').map(s => s.lines.join('\n')),
    notes: sections.filter(s => s.key === 'NOTES').map(text).join('\n'),
  };
}

function typeText(attributes) {
  const types = attributes.filter(a => /^[A-Za-z][A-Za-z0-9_.]*(\[\])?$/.test(a.trim()));
  if (types.length === 0) return 'object';
  return types[types.length - 1].trim().replace(/^System\.Management\.Automation\./, '').replace(/^System\.(Collections\.)?(Generic\.)?/, '');
}

export function parseParameters(paramBlock) {
  const result = [];
  for (const chunkRaw of splitTopLevel(paramBlock, ',')) {
    // drop comments, then read the leading [attributes] and the $Name
    let chunk = '';
    for (let i = 0; i < chunkRaw.length; i++) {
      const skipped = skipStringOrComment(chunkRaw, i);
      if (skipped !== i && (chunkRaw[i] === '#' || chunkRaw.startsWith('<#', i))) { i = skipped - 1; continue; }
      if (skipped !== i) { chunk += chunkRaw.slice(i, skipped); i = skipped - 1; continue; }
      chunk += chunkRaw[i];
    }
    chunk = chunk.trim();
    if (!chunk) continue;
    const attributes = [];
    let i = 0;
    while (i < chunk.length) {
      while (i < chunk.length && /\s/.test(chunk[i])) i++;
      if (chunk[i] === '[') { const b = balanced(chunk, i, '[', ']'); attributes.push(b.inner); i = b.end; continue; }
      break;
    }
    const nameMatch = chunk.slice(i).match(/^\$([A-Za-z_][A-Za-z0-9_]*)/);
    if (!nameMatch) continue;
    const facts = [];
    for (const attribute of attributes) {
      const p = attribute.match(/^\s*Parameter\s*\(([\s\S]*)\)\s*$/i);
      if (!p) continue;
      const set = (p[1].match(/ParameterSetName\s*=\s*['"]([^'"]+)['"]/i) || [])[1] || '';
      const mandatory = /Mandatory\s*=\s*\$true\b/i.test(p[1]);
      facts.push({ set, mandatory });
    }
    if (facts.length === 0) facts.push({ set: '', mandatory: false });
    result.push({ name: nameMatch[1], type: typeText(attributes), facts });
  }
  return result;
}

function syntaxLines(name, parameters) {
  let sets = [...new Set(parameters.flatMap(p => p.facts.map(f => f.set)).filter(Boolean))];
  if (sets.length === 0) sets = [''];
  const lines = [];
  for (const set of sets) {
    const rows = [];
    for (const p of parameters) {
      const fact = p.facts.find(f => f.set === set || f.set === '');
      if (fact) rows.push({ name: p.name, type: p.type, mandatory: fact.mandatory });
    }
    const ordered = [...rows.filter(r => r.mandatory), ...rows.filter(r => !r.mandatory)];
    const parts = [name];
    for (const r of ordered) {
      const t = r.type === 'switch' ? `-${r.name}` : `-${r.name} <${r.type}>`;
      parts.push(r.mandatory ? t : `[${t}]`);
    }
    lines.push(parts.join(' '));
  }
  return [...new Set(lines)];
}

// Trailing lines that read as a sentence are the description of an example; everything before them is code.
export function splitExample(text) {
  let lines = text.split('\n').map(l => l.replace(/\s+$/, ''));
  while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
  while (lines.length && !lines[0].trim()) lines.shift();
  const isProse = l => /^[A-Z][a-z]+ /.test(l.trim()) && /[.:)]$/.test(l.trim()) && !/-/.test(l.trim().split(' ')[0]);
  const description = [];
  while (lines.length > 1 && isProse(lines[lines.length - 1])) description.unshift(lines.pop().trim());
  const code = lines.filter(l => l.trim());
  const indent = Math.min(...code.map(l => l.match(/^\s*/)[0].length));
  return { code: code.map(l => l.slice(indent)), description: description.join(' ') };
}

function exampleHtml(code) {
  const out = []; let continues = false;
  for (const line of code) {
    if (continues || /^\s/.test(line)) out.push(`<span class="terminal-line terminal-continuation">${escapeHtml(line.trimStart())}</span>`);
    else out.push(`<span class="terminal-line"><span class="ps-prompt">PS&gt;</span> ${escapeHtml(line)}</span>`);
    continues = /(`|\||,|\{|\()\s*$/.test(line);
  }
  return `<div class="code-box terminal-example"><pre><code>${out.join('\n')}</code></pre></div>`;
}

function cliCommands(notes) {
  const found = [];
  for (const m of notes.matchAll(/^\s*Command run: (sf [^\r\n(]*?)\s*(?:\([^\r\n]*)?$/gm)) {
    const c = m[1].trim();
    if (c && !found.includes(c)) found.push(c);
  }
  return found;
}

// ---- the commands of a module ------------------------------------------------------------------------------------------------------------

export function moduleDirs(repoRoot = defaultRoot) {
  return fs.readdirSync(repoRoot).filter(d => /^psfdx/.test(d) && fs.existsSync(path.join(repoRoot, d, `${d}.psd1`))).sort();
}

export function exportsOf(dir, repoRoot = defaultRoot) {
  const manifest = fs.readFileSync(path.join(repoRoot, dir, `${dir}.psd1`), 'utf8');
  const block = manifest.match(/FunctionsToExport\s*=\s*@\(([\s\S]*?)\)/);
  return [...(block ? block[1] : '').matchAll(/'([^']+)'/g)].map(m => m[1]);
}

const byName = (a, b) => (a.toLowerCase() < b.toLowerCase() ? -1 : a.toLowerCase() > b.toLowerCase() ? 1 : 0);

export function commandsOf(dir, repoRoot = defaultRoot) {
  // psfdx-shared keeps its commands in several .ps1 files; every other module has one .psm1
  const folder = path.join(repoRoot, dir);
  const files = dir === 'psfdx-shared'
    ? fs.readdirSync(folder).filter(f => f.endsWith('.ps1') && !f.endsWith('.Tests.ps1')).map(f => path.join(folder, f))
    : [path.join(folder, `${dir}.psm1`)];
  const functions = new Map();
  for (const file of files) for (const [name, fn] of parseFunctions(fs.readFileSync(file, 'utf8'))) functions.set(name, fn);
  const commands = [];
  for (const name of [...exportsOf(dir, repoRoot)].sort(byName)) {
    const fn = functions.get(name);
    if (!fn) throw new Error(`${dir} exports ${name} but no function of that name was found`);
    if (!fn.help) throw new Error(`${name} has no comment-based help`);
    const help = parseHelp(fn.help);
    if (!help.synopsis) throw new Error(`${name} has no help synopsis`);
    const parameters = parseParameters(fn.params);
    const example = help.examples.length ? splitExample(help.examples[0]) : { code: [], description: '' };
    commands.push({
      name,
      synopsis: help.synopsis,
      syntax: syntaxLines(name, parameters),
      parameters: parameters.map(p => ({
        name: p.name,
        type: p.type,
        required: p.facts.every(f => f.mandatory),
        requiredInSome: !p.facts.every(f => f.mandatory) && p.facts.some(f => f.mandatory),
        description: help.parameters.get(p.name.toLowerCase()) || '',
      })),
      example,
      cli: cliCommands(help.notes),
    });
  }
  return commands;
}

export function renderEntry(c) {
  let html = `<details class="cmd" id="${escapeHtml(c.name)}"><summary><span class="cmd-name">${escapeHtml(c.name)}</span> <span class="cmd-synopsis">${escapeHtml(c.synopsis)}</span></summary><div class="cmd-body">`;
  html += `<h4>Syntax</h4><pre class="cmd-syntax"><code>${c.syntax.map(escapeHtml).join('\n')}</code></pre>`;
  if (c.parameters.length) {
    html += '<h4>Parameters</h4><dl class="cmd-params">';
    for (const p of c.parameters) {
      const flag = p.required ? ', required' : p.requiredInSome ? ', required in some parameter sets' : '';
      html += `<dt><code>-${escapeHtml(p.name)}</code> <span class="cmd-type">${escapeHtml(p.type)}${flag}</span></dt><dd>${escapeHtml(p.description)}</dd>`;
    }
    html += '</dl>';
  }
  if (c.example.code.length) {
    html += `<h4>Example</h4>${exampleHtml(c.example.code)}`;
    if (c.example.description) html += `<p class="cmd-example-note">${escapeHtml(c.example.description)}</p>`;
  }
  if (c.cli.length) html += `<h4>Salesforce CLI</h4><p class="cmd-cli">Runs ${c.cli.map(x => `<code>${escapeHtml(x)}</code>`).join(', ')}.</p>`;
  return html + '</div></details>';
}

export function renderFragment(commands) {
  return [
    START,
    `<p class="ref-note">${commands.length} commands, in alphabetical order. Each entry is generated from the command's own help, so it matches <code>Get-Help &lt;command&gt; -Full</code>. Every command also takes the common parameters, such as <code>-Verbose</code>.</p>`,
    '<nav aria-label="Command index"><ul class="cmd-index">',
    commands.map(c => `<li><a href="#${escapeHtml(c.name)}">${escapeHtml(c.name)}</a></li>`).join('\n'),
    '</ul></nav>',
    '<div class="cmd-list">',
    commands.map(renderEntry).join('\n'),
    '</div>',
    END,
  ].join('\n');
}

// Puts the reference of a module between the markers of its page.
export function fillPage(html, dir, repoRoot = defaultRoot) {
  const start = html.indexOf(START); const end = html.indexOf(END);
  if (start < 0 || end < start) return html;
  return html.slice(0, start) + renderFragment(commandsOf(dir, repoRoot)) + html.slice(end + END.length);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--json')) {
    const all = {};
    for (const dir of moduleDirs()) all[dir] = commandsOf(dir);
    process.stdout.write(JSON.stringify(all, null, 1));
  } else {
    console.error('Usage: node site/reference.mjs --json');
    process.exit(2);
  }
}
