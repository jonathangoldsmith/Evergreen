// The outbox store over the host's `io` object (the one the memory store uses; contract in src/store/node/io-node.mjs).
// No node: import, so it runs on the phone. The file is <dir>/outbox.json; `dir` is the user's memory folder, which
// already exists. A store is {save(outbox), load(), sync(outbox)}; outbox.mjs says what results it expects.
import { checkUser } from './events.mjs';
import { plainOutbox } from './outbox.mjs';

const FAIL = (error, more = {}) => ({ ok: false, error, ...more });
const TOLERATED = ['ENOTSUP', 'EOPNOTSUPP'];

export function createIoStore({ io, dir, userId }) {
  checkUser(userId);
  const path = `${dir}/outbox.json`;
  const tmp = `${dir}/.outbox.json.tmp`;
  const read = (p) => { try { return io.readFile(p); } catch (e) { return e?.code === 'ENOENT' ? null : undefined; } };

  // Directory sync after the rename; the platform's own "not supported" codes are fine, anything else means unsynced.
  const syncDir = () => { try { io.fsyncDir(dir); return true; } catch (e) { return TOLERATED.includes(e?.code); } };

  // Re-read the final file and say what is true: it is the intended text, something else, or unreadable.
  function reconcile(text, intended, dirSynced) {
    const raw = read(path);
    if (raw === undefined || raw === null) return FAIL('outbox state unrecovered', { unrecovered: true });
    if (raw === text) return dirSynced ? { ok: true } : FAIL('outbox directory sync failed', { unsynced: true, outbox: intended });
    try {
      const onDisk = plainOutbox(JSON.parse(raw));
      if (onDisk.user !== userId) throw new Error('invalid');
      return FAIL('outbox on disk differs from the intended content', { outbox: onDisk });
    } catch {
      return FAIL('outbox state unrecovered', { unrecovered: true });
    }
  }

  // Atomic save: write a temp file, flush it, read it back, rename it over the old file, sync the folder, read the result.
  function save(given) {
    let outbox;
    try { outbox = plainOutbox(given); } catch { return FAIL('outbox could not be saved'); }
    if (outbox.user !== userId) return FAIL('outbox could not be saved');
    const text = JSON.stringify(outbox);
    try {
      io.remove(tmp);
      io.writeFile(tmp, text);
      io.fsyncFile(tmp);
      if (io.readFile(tmp) !== text) throw new Error('mismatch');
    } catch {
      try { io.remove(tmp); } catch { /* nothing more to do */ }
      return FAIL('outbox could not be saved');
    }
    try {
      io.rename(tmp, path);
    } catch {
      try { io.remove(tmp); } catch { /* best effort */ }
      return reconcile(text, outbox, false);       // a rename that threw may still have happened
    }
    return reconcile(text, outbox, syncDir());
  }

  // {ok: true, outbox} (null when there is no file yet) or {ok: false, error}.
  function load() {
    try { io.remove(tmp); } catch { return FAIL('outbox could not be read'); }
    const text = read(path);
    if (text === null) return { ok: true, outbox: null };
    if (text === undefined) return FAIL('outbox could not be read');
    try {
      const outbox = plainOutbox(JSON.parse(text));
      if (outbox.user !== userId) throw new Error('invalid');
      return syncDir() ? { ok: true, outbox } : FAIL('outbox directory sync failed');
    } catch {
      return FAIL('outbox is invalid');
    }
  }

  // Retry the folder sync for an outbox that was written but not known durable, and check the file again.
  function sync(given) {
    let outbox;
    try { outbox = plainOutbox(given); } catch { return FAIL('outbox could not be synced'); }
    return reconcile(JSON.stringify(outbox), outbox, syncDir());
  }

  return { save, load, sync };
}
