import { sanitizeEvent } from '../events.mjs';

// Write-only sender. Refuses to run without a key. The key comes only from the environment
// (AMPLITUDE_API_KEY in env, which defaults to process.env) and never appears in any output.
// Every event is validated and rebuilt from known fields before anything is returned or sent.
export const URL_ENDPOINT = 'https://api2.amplitude.com/2/httpapi';
export const BATCH_SIZE = 500;
const REDACTED = '[redacted]';

function chunks(events) {
  const out = [];
  for (let i = 0; i < events.length; i += BATCH_SIZE) out.push(events.slice(i, i + BATCH_SIZE));
  return out;
}

export async function send(events, { fetchImpl, dryRun = false, env = process.env } = {}) {
  if (!Array.isArray(events)) throw new Error('events must be an array');
  const clean = events.map(sanitizeEvent); // throws on the first bad event: nothing is sent or returned
  const batches = chunks(clean);
  if (dryRun) {
    return {
      dryRun: true,
      sent: 0,
      batches: batches.length,
      payloads: batches.map((b) => ({ api_key: REDACTED, events: b })),
    };
  }
  const key = env?.AMPLITUDE_API_KEY;
  if (!key) throw new Error('AMPLITUDE_API_KEY is not set; nothing was sent');
  if (typeof fetchImpl !== 'function') throw new Error('no fetch implementation given; nothing was sent');
  // Delivery is reported per batch. The run stops at the first failed batch; later batches are reported as not
  // attempted. Nothing here throws once sending has started, so the caller always learns what was acknowledged.
  const acked = [];
  const failed = [];
  let sent = 0;
  let stopped = false;
  for (const [i, batch] of batches.entries()) {
    const ids = batch.map((e) => e.insert_id);
    if (stopped) {
      failed.push({ batch: i, insert_ids: ids, error: 'not attempted after an earlier failure' });
      continue;
    }
    let error = null;
    try {
      const res = await fetchImpl(URL_ENDPOINT, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ api_key: key, events: batch }),
      });
      if (!res || res.status !== 200) {
        error = Number.isInteger(res?.status) ? `Amplitude answered ${res.status}` : 'Amplitude gave no valid answer';
      }
    } catch {
      error = 'Amplitude request failed'; // never echo the fetch error: it may carry the key
    }
    if (error) {
      failed.push({ batch: i, insert_ids: ids, error });
      stopped = true;
    } else {
      acked.push({ batch: i, insert_ids: ids });
      sent += batch.length;
    }
  }
  return { dryRun: false, sent, batches: batches.length, acked, failed };
}
