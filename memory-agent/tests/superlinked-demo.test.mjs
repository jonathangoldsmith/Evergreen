import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyDemoFeedback, SAMPLE_FEEDBACK } from '../scripts/lib/superlinked-demo.mjs';

test('Superlinked gets only the fixed sample text and returns allowed labels', async () => {
  const labels = await classifyDemoFeedback({
    apiKey: 'synthetic-secret',
    request: async (url, options) => {
      assert.equal(url, 'https://api.superlinked.com/v1/chat/completions');
      assert.equal(options.redirect, 'error');
      assert.equal(options.headers.authorization, 'Bearer synthetic-secret');
      const { messages } = JSON.parse(options.body);
      assert.deepEqual(JSON.parse(messages[0].content.split('\n')[1]), SAMPLE_FEEDBACK);
      return { ok: true, json: async () => ({ choices: [{ message: { content: '{"labels":["too_early","too_early"]}' } }] }) };
    },
  });
  assert.deepEqual(labels, ['too_early', 'too_early']);
});

test('missing key, provider failure and malformed output fail without revealing secret or body', async () => {
  await assert.rejects(classifyDemoFeedback({ apiKey: '', request: () => assert.fail() }), /Missing or invalid/);
  await assert.rejects(classifyDemoFeedback({
    apiKey: 'fake-secret', request: async () => ({ ok: false, status: 401, json: () => assert.fail() }),
  }), { message: 'Superlinked rejected the request (HTTP 401)' });
  await assert.rejects(classifyDemoFeedback({
    apiKey: 'fake-secret', request: async () => ({ ok: true, json: async () => ({ choices: [{ message: { content: '{"labels":["leak","too_early"]}' } }] }) }),
  }), { message: 'Superlinked returned invalid demo labels' });
});
