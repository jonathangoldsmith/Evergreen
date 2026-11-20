// A general secret scanner used by the Amplitude tests. Not a test file itself.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const R = (...parts) => new RegExp(parts.join(''), 'g');
export const RULES = [
  ['32-hex token', R('(?<![0-9A-Za-z])[0-9a-fA-F]{32}(?![0-9A-Za-z])')],
  ['named assignment with a long value', R('(?:AMPLITUDE|API_?KEY|SECRET|TOKEN)[A-Za-z0-9_]*["\']?\\s*[=:]\\s*["\']?[A-Za-z0-9+/_=-]{20,}')],
  ['long base64-looking string', R('(?<![A-Za-z0-9+/_-])[A-Za-z0-9+/]{40,}={0,2}(?![A-Za-z0-9+/_-])')],
  ['Google key shape', R('AI', 'za[0-9A-Za-z_-]{20,}')],
  ['sk- key shape', R('sk', '-[A-Za-z0-9_-]{20,}')],
  ['GitHub token shape', R('gh[pousr]', '_[A-Za-z0-9]{20,}')],
  ['AWS key shape', R('AK', 'IA[0-9A-Z]{16}')],
  ['Slack token shape', R('xox[abprs]', '-[A-Za-z0-9-]{10,}')],
  ['private key block', R('-----BEGIN [A-Z ]*PRIVATE', ' KEY-----')],
];

// Known test vectors that are allowed to look like secrets.
export const ALLOW = new Set([]);

// Join 'a' + 'b' and "a" + "b" so a key split across string pieces is still seen.
export function collapse(text) {
  return text.replace(/(["'`])\s*\+\s*\1/g, '').replace(/(["'`])\s*\+\s*(["'`])/g, '');
}

export function scanText(text, allow = ALLOW) {
  const hits = [];
  const t = collapse(text);
  for (const [name, re] of RULES) {
    for (const m of t.matchAll(re)) if (!allow.has(m[0])) hits.push(name);
  }
  return [...new Set(hits)];
}

export function walk(dir, skip = ['.git', 'node_modules']) {
  return readdirSync(dir).flatMap((n) => {
    if (skip.includes(n)) return [];
    const p = join(dir, n);
    return statSync(p).isDirectory() ? walk(p, skip) : [p];
  });
}

export function scanTree(root, allow = ALLOW) {
  const out = [];
  for (const f of walk(root)) {
    const buf = readFileSync(f);
    if (buf.includes(0)) continue; // binary
    for (const name of scanText(buf.toString('utf8'), allow)) out.push(`${name}: ${relative(root, f)}`);
  }
  return out;
}
