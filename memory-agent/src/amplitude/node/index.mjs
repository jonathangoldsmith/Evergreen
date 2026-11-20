// Node-only entry point, used by tests and the dry-run demo. It wires the pure core to Node's crypto and fs and to
// the fetch sender, keeping the call shapes (env, root) that the tests use. None of this runs on the phone.
import * as core from '../index.mjs';
import { nodeHost } from './host.mjs';
import { createFileStore } from './file-store.mjs';
import { send } from './sender.mjs';

export { EVENTS, buildEvent, canonicalActivity, newSent, REQUIRED, MIN_WORKOUT_MIN, sanitizeEvent, newOutbox, ackOutbox } from '../index.mjs';
export { send, BATCH_SIZE, URL_ENDPOINT } from './sender.mjs';
export { nodeHost, nodeHmac } from './host.mjs';
export { createFileStore } from './file-store.mjs';

const FAIL = (error) => ({ ok: false, error });

export const opaqueId = (prefix, seed, env = process.env) => core.opaqueId(prefix, seed, nodeHost(env));

export function eventsFromSnapshot(snapshot, userId, { env = process.env, sent, source } = {}) {
  return core.eventsFromSnapshot(snapshot, userId, { host: nodeHost(env), sent, source });
}

export function stageSnapshot(outbox, snapshot, { env = process.env, source } = {}) {
  return core.stageSnapshot(outbox, snapshot, { host: nodeHost(env), source });
}

export function commitSnapshot(root, outbox, snapshot, { env = process.env, fs, platform, source } = {}) {
  const store = createFileStore({ root, userId: core.checkOutbox(outbox).user, fs, platform });
  return core.commitSnapshot(store, outbox, snapshot, { host: nodeHost(env), source });
}

export async function deliverOutbox(root, outbox, { fetchImpl, env = process.env, fs, platform } = {}) {
  const store = createFileStore({ root, userId: core.checkOutbox(outbox).user, fs, platform });
  return core.deliverOutbox(store, outbox, (events) => send(events, { fetchImpl, env }));
}

export function saveOutbox(root, outbox, { fs, platform } = {}) {
  let plain;
  let store;
  try {
    plain = core.plainOutbox(outbox);
    store = createFileStore({ root, userId: plain.user, fs, platform });
  } catch {
    return FAIL('outbox could not be saved');
  }
  return store.save(plain);
}

export function loadOutbox(root, userId, { fs, platform } = {}) {
  let store;
  try {
    store = createFileStore({ root, userId, fs, platform });
  } catch {
    return FAIL('outbox could not be read');
  }
  return core.loadOutbox(store, userId);
}

export function syncOutbox(root, outbox, { fs, platform } = {}) {
  let store;
  try {
    store = createFileStore({ root, userId: core.checkOutbox(outbox).user, fs, platform });
  } catch {
    return FAIL('outbox could not be synced');
  }
  return core.syncOutbox(store, outbox);
}

export function forgetDay(root, outbox, localDate, { fs, platform } = {}) {
  const store = createFileStore({ root, userId: core.checkOutbox(outbox).user, fs, platform });
  return core.forgetDay(store, outbox, localDate);
}

export function restoreForgotten(root, outbox, { fs, platform } = {}) {
  const store = createFileStore({ root, userId: core.checkOutbox(outbox).user, fs, platform });
  return core.restoreForgotten(store, outbox);
}
