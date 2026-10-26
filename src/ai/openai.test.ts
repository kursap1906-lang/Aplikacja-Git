import assert from 'node:assert/strict';
import test from 'node:test';
import { z } from 'zod';
import {
  analysisCostMicros, analysisModel, buildAnalysisRequest, countAnalysisInput,
  generateAnalysis, maximumAnalysisCostMicros, maximumInputTokens,
  maximumOutputTokens, OpenAiRequestError, parseAnalysisResult, parseAnalysisUsage,
} from './openai.ts';

const resultSchema = z.object({ summary: z.string().min(1) }).strict();
const request = () => buildAnalysisRequest({
  instructions: 'Summarize the synthetic task. Do not execute tools.',
  input: [{ type: 'input_text', text: 'Create a page with a title.' }],
  name: 'synthetic_summary',
  schema: { type: 'object', properties: { summary: { type: 'string' } }, required: ['summary'], additionalProperties: false },
});
const result = () => ({
  id: 'resp_fixture', model: analysisModel, status: 'completed',
  usage: { input_tokens: 1000, output_tokens: 100, input_tokens_details: { cached_tokens: 100 } },
  output: [{
    type: 'message', role: 'assistant', status: 'completed',
    content: [{ type: 'output_text', text: '{"summary":"A page with a title."}' }],
  }],
});

test('analysis uses a pinned economical model and identical structured context for counting', async () => {
  const calls: { url: string; body: unknown }[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer fixture-key');
    assert.equal(init?.redirect, 'error');
    calls.push({ url: String(url), body: JSON.parse(String(init?.body)) });
    return Response.json(String(url).endsWith('/input_tokens')
      ? { object: 'response.input_tokens', input_tokens: 1000 } : result());
  };
  const payload = request();
  const counted = await countAnalysisInput({ key: 'fixture-key', request: payload, fetcher });
  const raw = await generateAnalysis({ key: 'fixture-key', request: payload, fetcher });
  assert.deepEqual(calls[0], { url: 'https://api.openai.com/v1/responses/input_tokens', body: payload });
  assert.deepEqual(calls[1], {
    url: 'https://api.openai.com/v1/responses',
    body: { ...payload, store: false, max_output_tokens: maximumOutputTokens, truncation: 'disabled' },
  });
  assert.equal(counted.tokens, 1000);
  assert.equal(counted.maximumCostMicros, analysisCostMicros(1000, maximumOutputTokens));
  assert.deepEqual(parseAnalysisResult(raw, resultSchema), { summary: 'A page with a title.' });
  assert.deepEqual(parseAnalysisUsage(raw), { inputTokens: 1000, outputTokens: 100, cachedTokens: 100, costMicros: 1133 });
});

test('microdollar accounting rounds up and includes uncached, cached and output token prices', () => {
  assert.equal(analysisCostMicros(1, 0), 1);
  assert.equal(analysisCostMicros(0, 1), 5);
  assert.equal(analysisCostMicros(1000, 1000), 5250);
  assert.equal(analysisCostMicros(1000, 1000, 1000), 4575);
  assert.ok(analysisCostMicros(maximumInputTokens, maximumOutputTokens) <= maximumAnalysisCostMicros);
  for (const args of [[-1, 0, 0], [0, -1, 0], [0, 0, 1], [1.5, 0, 0], [maximumInputTokens + 1, 0, 0], [0, maximumOutputTokens + 1, 0], [NaN, 0, 0]]) {
    assert.throws(() => analysisCostMicros(args[0], args[1], args[2]), { code: 'OPENAI_USAGE_INVALID' });
  }
});

test('counting rejects malformed or excessive input without generating a response', async () => {
  for (const data of [
    {}, { object: 'other', input_tokens: 1 }, { object: 'response.input_tokens', input_tokens: -1 },
    { object: 'response.input_tokens', input_tokens: '100' },
    { object: 'response.input_tokens', input_tokens: maximumInputTokens + 1 },
  ]) {
    let calls = 0;
    await assert.rejects(countAnalysisInput({
      key: 'fixture-key', request: request(),
      fetcher: async (url) => {
        calls++;
        assert.ok(String(url).endsWith('/input_tokens'));
        return Response.json(data);
      },
    }));
    assert.equal(calls, 1);
  }
});

test('network ambiguity is explicit and never automatically retried', async () => {
  for (const generate of [false, true]) {
    let calls = 0;
    const options = {
      key: 'fixture-key', request: request(),
      fetcher: async () => { calls++; throw new TypeError('connection interrupted'); },
    };
    await assert.rejects(generate ? generateAnalysis(options) : countAnalysisInput(options), (error: unknown) =>
      error instanceof OpenAiRequestError && error.chargeUncertain === generate && error.code === 'OPENAI_UNAVAILABLE');
    assert.equal(calls, 1);
  }
});

test('HTTP failures distinguish rejected requests from uncertain server failures without exposing error bodies', async () => {
  for (const status of [400, 401, 403, 404, 408, 429, 499, 500, 502]) {
    let calls = 0;
    await assert.rejects(generateAnalysis({
      key: 'fixture-key', request: request(),
      fetcher: async () => { calls++; return new Response('private provider error detail', { status }); },
    }), (error: unknown) => error instanceof OpenAiRequestError &&
      error.chargeUncertain === [408, 499, 500, 502].includes(status) && !error.message.includes('private'));
    assert.equal(calls, 1);
  }
});

test('malformed or oversized provider responses cannot look like success', async () => {
  for (const data of ['not JSON', ' '.repeat(2 * 1024 * 1024 + 1)]) {
    await assert.rejects(generateAnalysis({
      key: 'fixture-key', request: request(), fetcher: async () => new Response(data),
    }), (error: unknown) => error instanceof OpenAiRequestError &&
      error.chargeUncertain && error.code === 'OPENAI_RESPONSE_INVALID');
  }
});

test('incomplete, refused, tool, ambiguous and schema-invalid outputs never become saved results', () => {
  for (const response of [
    { ...result(), status: 'incomplete' },
    { ...result(), model: 'unapproved-expensive-model' },
    { ...result(), output: [] },
    { ...result(), output: [...result().output, ...result().output] },
    { ...result(), output: [{ type: 'function_call' }] },
    { ...result(), output: [{ type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'refusal', refusal: 'No.' }] }] },
    { ...result(), output: [{ type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: '{}' }] }] },
    { ...result(), output: [{ type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: 'not JSON' }] }] },
  ]) {
    assert.throws(() => parseAnalysisResult(response, resultSchema), { code: 'OPENAI_RESULT_INVALID' });
  }
});

test('usage is accounted separately even when a paid generation produces an invalid result', () => {
  const raw = { ...result(), status: 'incomplete' };
  assert.equal(parseAnalysisUsage(raw).costMicros, 1133);
  assert.throws(() => parseAnalysisResult(raw, resultSchema));
  for (const value of [
    {}, { ...result(), model: 'other' }, { ...result(), usage: null },
    { ...result(), usage: { input_tokens: 1, output_tokens: 1 } },
    { ...result(), usage: { input_tokens: 1, output_tokens: 1, input_tokens_details: { cached_tokens: 2 } } },
  ]) {
    assert.throws(() => parseAnalysisUsage(value), { code: 'OPENAI_USAGE_INVALID' });
  }
});
