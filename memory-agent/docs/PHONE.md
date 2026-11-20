# Phone host

The bundle sets six globals: `memoryRoll`, `memoryTap`, `memoryForget`, `memoryPlannerText`, `memoryFlush` (unsent events) and `memoryAck` (`acked` insert ids). Each takes and returns one JSON string (arguments: `src/phone/entry.mjs`), never throws; a failure is `{"ok":false,"error":"<name>"}`.

Set `globalThis.memoryIO` first (synchronous): `readFile` text; `writeFile(path, text)` new file only; `fsyncFile`; `fsyncDir`; `rename(from, to)` atomic; `remove` quiet if absent; `mkdir` one level; `lstat` `{isFile, isDirectory, isSymbolicLink, dev, ino}`; `realpath`; `readdir` `[{name, ...lstat fields}]`; `sha256(text)` hex; `platform`. A throw (`code`: `ENOENT`, `EEXIST`) fails that call safely. For events add `idSecret` (16+ characters) and `hmac(secret, data)` (hex); without them no events.

```js
const fs = new Map();
const fail = (code) => { throw Object.assign(new Error(code), { code }); };
const get = (p) => fs.get(p) ?? fail('ENOENT');
const put = (p, x) => (fs.has(p) ? fail('EEXIST') : fs.set(p, { isFile: !x.dir, isDirectory: !!x.dir, isSymbolicLink: false, dev: 1, ino: fs.size, ...x }));
put('/', { dir: 1 });
globalThis.memoryIO = {
  platform: 'posix',
  readFile: (p) => get(p).text,
  writeFile: (p, text) => put(p, { text }),
  fsyncFile() {}, fsyncDir() {},
  rename: (a, b) => { fs.set(b, get(a)); fs.delete(a); },
  remove: (p) => { fs.delete(p); },
  mkdir: (p) => put(p, { dir: 1 }),
  lstat: get,
  realpath: (p) => (get(p), p),
  readdir: (p) => [...fs.keys()].filter((k) => k.startsWith(`${p}/`) && !/\/./.test(k.slice(p.length + 1))).map((k) => ({ name: k.slice(p.length + 1), ...fs.get(k) })),
  sha256: (text) => hostSha256(text),
};
const call = (name, more) => JSON.parse(globalThis[name](JSON.stringify({ root: '/mem', user: 'usr_0123456789abcdef', ...more })));
call('memoryRoll', { snapshot, now: '2026-11-18T00:00:00-08:00' });
const planner = call('memoryPlannerText', {});
```
