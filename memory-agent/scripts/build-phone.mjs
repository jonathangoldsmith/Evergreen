// Bundles src/phone/entry.mjs into one script (an iife) that iOS JavaScriptCore can load: node scripts/build-phone.mjs [out-file]
// Needs esbuild (a devDependency: npm install). It sets the six global functions and imports nothing at run time.
import { build } from 'esbuild';

export async function buildPhone(outfile) {
  const result = await build({
    entryPoints: [new URL('../src/phone/entry.mjs', import.meta.url).pathname],
    bundle: true, format: 'iife', target: 'es2022', write: outfile !== undefined, outfile, logLevel: 'silent',
  });
  return result.outputFiles?.[0]?.text;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const out = process.argv[2] ?? 'dist/phone.js';
  await buildPhone(out);
  console.log(`wrote ${out}`);
}
