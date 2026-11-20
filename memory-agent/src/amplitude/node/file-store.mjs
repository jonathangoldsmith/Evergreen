// Node-only: a file store for the outbox, with atomic writes and fsync. Used by tests and the dry-run demo.
// The file is always <root>/<usr_id>/outbox.json, derived from the validated opaque user id: no caller-supplied path.
// A store is {save(outbox), load(), sync(outbox)}; see outbox.mjs for the results the core expects.
import * as nodeFs from 'node:fs';
import { dirname, join } from 'node:path';
import { checkUser } from '../events.mjs';
import { checkOutbox, plainOutbox } from '../outbox.mjs';

const FAIL = (error, more = {}) => ({ ok: false, error, ...more });

// Directory sync: a rename or a new directory is only durable once the parent directory entry is on disk. The
// platform's own "not supported" codes are tolerated; any other failure is a failure.
const NOT_SUPPORTED = ['ENOTSUP', 'EOPNOTSUPP'];
const WIN32_NOT_SUPPORTED = ['EINVAL', 'EPERM', 'EISDIR'];
function syncDir(fs, dir, platform) {
  let fd;
  try {
    fd = fs.openSync(dir, 'r');
    fs.fsyncSync(fd);
  } catch (e) {
    const code = e?.code;
    if (NOT_SUPPORTED.includes(code) || (platform === 'win32' && WIN32_NOT_SUPPORTED.includes(code))) return;
    throw new Error('directory sync failed');
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch { /* already reported */ } }
  }
}

// Creates every missing directory one level at a time, outermost first, and syncs the parent of each directory it
// created, so each new directory entry is durable.
function ensureDir(fs, target, platform) {
  if (fs.existsSync(target)) return;
  const parent = dirname(target);
  if (parent !== target) ensureDir(fs, parent, platform);
  fs.mkdirSync(target, { mode: 0o700 });
  syncDir(fs, parent, platform);
}

export function createFileStore({ root, userId, fs = nodeFs, platform = process.platform }) {
  if (typeof root !== 'string' || root.length === 0) throw new Error('outbox root must be a non-empty string');
  checkUser(userId);
  const dir = join(root, userId);
  const path = join(dir, 'outbox.json');
  const TMP_NAME = '.outbox.json.tmp';
  const tmp = join(dir, TMP_NAME); // a fixed name: a restart finds and removes what a crash left behind

  // Re-read the final file (twice if the first read fails) and decide what is true.
  function reconcile(text, intended, errorText, dirSynced) {
    let raw = null;
    for (let attempt = 0; attempt < 2 && raw === null; attempt += 1) {
      try { raw = fs.readFileSync(path, 'utf8'); } catch { raw = null; }
    }
    if (raw === null) return FAIL('outbox state unrecovered', { unrecovered: true });
    if (raw === text) return dirSynced ? { ok: true } : FAIL(errorText, { unsynced: true, outbox: intended });
    try {
      const onDisk = checkOutbox(JSON.parse(raw));
      if (onDisk.status !== undefined || onDisk.user !== userId) throw new Error('invalid');
      return FAIL('outbox on disk differs from the intended content', { outbox: onDisk });
    } catch {
      return FAIL('outbox state unrecovered', { unrecovered: true });
    }
  }

  // Abandoned temp files of this user (regular files whose name starts with the temp name, including the old
  // per-process names) are removed and the folder is synced before any operation is accepted. A forget is complete
  // only when none remain. True when there is nothing left to remove or everything was removed durably.
  function cleanTemps() {
    try {
      if (!fs.existsSync(dir)) return true;
      let removed = false;
      for (const name of fs.readdirSync(dir)) {
        if (!name.startsWith(TMP_NAME)) continue;
        const p = join(dir, name);
        if (!fs.lstatSync(p).isFile()) continue;
        fs.unlinkSync(p);
        removed = true;
      }
      if (removed) syncDir(fs, dir, platform);
      return true;
    } catch {
      return false;
    }
  }

  // On every save: fsync the user folder and EVERY ancestor up to the filesystem root. It is cheap and idempotent,
  // and it makes any folder whose earlier sync failed durable on the retry. True only if all succeed.
  function chain() {
    const out = [dir];
    for (let d = dirname(dir); d !== out[out.length - 1]; d = dirname(d)) out.push(d);
    return out;
  }
  function syncChain() {
    let ok = true;
    for (const d of chain()) {
      try { syncDir(fs, d, platform); } catch { ok = false; }
    }
    return ok;
  }

  // Atomic save: write a temp file in the user's folder, fsync it, read it back and verify, rename it over the old
  // file, fsync the folder, then reconcile by reading the final file. A failure before the rename leaves the old file
  // untouched; after it the file on disk has changed, so a problem is reconciled by re-reading.
  function save(given) {
    // the store never trusts its caller: the outbox is validated and rebuilt from the allowlist before it is written
    let outbox;
    try {
      outbox = plainOutbox(given);
    } catch {
      return FAIL('outbox could not be saved');
    }
    if (outbox.user !== userId) return FAIL('outbox could not be saved');
    const text = JSON.stringify(outbox);
    if (!cleanTemps()) return FAIL('outbox could not be saved');
    try {
      ensureDir(fs, dir, platform);
    } catch {
      return FAIL('outbox could not be saved');
    }
    try {
      const fd = fs.openSync(tmp, 'w', 0o600);
      try {
        fs.writeSync(fd, text);
        fs.fsyncSync(fd);
      } finally {
        fs.closeSync(fd);
      }
      if (fs.readFileSync(tmp, 'utf8') !== text) throw new Error('mismatch');
    } catch {
      try { fs.unlinkSync(tmp); syncDir(fs, dir, platform); } catch { /* the temp file may not exist */ }
      return FAIL('outbox could not be saved');
    }
    try {
      fs.renameSync(tmp, path);
    } catch {
      try { fs.unlinkSync(tmp); syncDir(fs, dir, platform); } catch { /* best effort */ }
      return reconcile(text, outbox, 'outbox could not be saved', false); // a rename that threw may still have happened
    }
    return reconcile(text, outbox, 'outbox directory sync failed', syncChain());
  }

  // {ok: true, outbox} (null when no file exists) or {ok: false, error}. The folder is synced first, so what is
  // returned is known to be durable.
  function load() {
    if (!cleanTemps()) return FAIL('outbox could not be read');
    let text;
    try {
      text = fs.readFileSync(path, 'utf8');
    } catch (e) {
      return e?.code === 'ENOENT' ? { ok: true, outbox: null } : FAIL('outbox could not be read');
    }
    let outbox;
    try {
      outbox = plainOutbox(JSON.parse(text)); // rebuilt from the allowlist; a file with a status or raw data is invalid
      if (outbox.user !== userId) throw new Error('invalid');
    } catch {
      return FAIL('outbox is invalid');
    }
    if (!syncChain()) return FAIL('outbox directory sync failed');
    return { ok: true, outbox };
  }

  // Retry the folder sync for an outbox that was written but not known durable, and verify the file again.
  function sync(given) {
    let outbox;
    try {
      outbox = plainOutbox(given);
    } catch {
      return FAIL('outbox could not be synced');
    }
    if (!cleanTemps()) return FAIL('outbox could not be synced');
    return reconcile(JSON.stringify(outbox), outbox, 'outbox directory sync failed', syncChain());
  }

  return { save, load, sync };
}
