// Node-only: the host pieces the pure core asks for. Used by tests and the dry-run demo, not on the phone.
import { createHmac } from 'node:crypto';

export const nodeHmac = (secret, data) => createHmac('sha256', secret).update(data).digest('hex');

// env is an object like process.env; TRACKER_ID_SECRET is the id secret.
export function nodeHost(env = process.env) {
  return { hmac: nodeHmac, secret: env?.TRACKER_ID_SECRET };
}
