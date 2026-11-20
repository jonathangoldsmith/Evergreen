// Only fixed fictional feedback ever goes to the hosted classifier. This module
// is for the CLI demo, never the phone bundle or production memory data.
export const SAMPLE_FEEDBACK = Object.freeze([
  'That 7:30 Saturday elliptical was too early for me.',
  "Another 7:30 Saturday workout? That's earlier than I can do.",
]);
const allowed = ['too_early', 'too_late', 'other'];
const resultSchema = {
  type: 'object',
  properties: { labels: { type: 'array', items: { type: 'string', enum: allowed }, minItems: 2, maxItems: 2 } },
  required: ['labels'],
  additionalProperties: false,
};

export async function classifyDemoFeedback({ apiKey, request = fetch }) {
  if (typeof apiKey !== 'string' || !apiKey.trim() || /\s/.test(apiKey.trim())) {
    throw new Error('Missing or invalid SUPERLINKED_API_KEY');
  }
  let response;
  try {
    response = await request('https://api.superlinked.com/v1/chat/completions', {
      method: 'POST',
      headers: { authorization: 'Bearer ' + apiKey.trim(), 'content-type': 'application/json' },
      redirect: 'error',
      signal: AbortSignal.timeout(60_000),
      body: JSON.stringify({
        model: 'Qwen/Qwen3.8-27B-FP8',
        messages: [{ role: 'user', content: 'Classify these fictional workout replies as too_early, too_late or other. Return the labels in order.\n' + JSON.stringify(SAMPLE_FEEDBACK) }],
        temperature: 0,
        max_completion_tokens: 256,
        response_format: { type: 'json_schema', json_schema: { name: 'demo_feedback', schema: resultSchema, strict: true } },
      }),
    });
  } catch {
    throw new Error('Superlinked request did not complete');
  }
  if (!response.ok) throw new Error('Superlinked rejected the request (HTTP ' + response.status + ')');
  try {
    const raw = await response.json();
    const labels = JSON.parse(raw.choices[0].message.content).labels;
    if (!Array.isArray(labels) || labels.length !== SAMPLE_FEEDBACK.length || labels.some(x => !allowed.includes(x))) {
      throw new TypeError();
    }
    return labels;
  } catch {
    throw new Error('Superlinked returned invalid demo labels');
  }
}
