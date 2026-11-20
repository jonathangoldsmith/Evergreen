import { send } from '../../src/amplitude/node/sender.mjs';
import { userIdOf } from './trial-core.mjs';
import { CALENDAR_DEMO_ANALYTICS_USER } from './calendar-demo-analytics.mjs';

// Only upload to a project that can already read the earlier Memory Agent
// trial. Checking with both keys ties the write key to the historical project.
export async function deliverCalendarDemo(events, { env = process.env, request = fetch } = {}) {
  const apiKey = env.AMPLITUDE_API_KEY?.trim();
  const secret = env.AMPLITUDE_SECRET_KEY?.trim();
  if (!apiKey || !secret) throw new Error('Amplitude credentials missing; nothing was sent');
  if (events.some(e => e.user_id !== CALENDAR_DEMO_ANALYTICS_USER)) throw new Error('Only synthetic calendar demo events can be sent');
  const call = (url, options) => request(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(15_000) });
  const auth = { authorization: 'Basic ' + Buffer.from(apiKey + ':' + secret).toString('base64') };
  try {
    const historicalUser = userIdOf('sedentary');
    const res = await call('https://amplitude.com/api/2/usersearch?user=' + encodeURIComponent(historicalUser), { headers: auth });
    if (!res.ok || !(await res.json()).matches?.some(row => row.user_id === historicalUser && row.amplitude_id)) {
      throw new Error();
    }
  } catch {
    throw new Error('Could not verify the existing Memory Agent Amplitude project; nothing was sent');
  }
  return send(events, { fetchImpl: call, env: { AMPLITUDE_API_KEY: apiKey } });
}
