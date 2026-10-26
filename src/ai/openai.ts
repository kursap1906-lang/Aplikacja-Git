import { z } from 'zod';
import { ApiError } from '../http/errors.ts';

export const analysisModel = 'gpt-5.4-mini-2026-03-17';
export const maximumInputTokens = 272_000;
export const maximumOutputTokens = 16_384;
export const maximumAnalysisCostMicros = 1_000_000;
export const monthlyAnalysisBudgetMicros = 10_000_000;

export type AnalysisInput =
  | { type: 'input_text'; text: string }
  | { type: 'input_file'; filename: string; file_data: string }
  | { type: 'input_image'; image_url: string; detail: 'auto' };

export type AnalysisRequest = {
  model: typeof analysisModel;
  instructions: string;
  input: { role: 'user'; content: AnalysisInput[] }[];
  reasoning: { effort: 'medium' };
  text: { format: { type: 'json_schema'; name: string; strict: true; schema: Record<string, unknown> } };
};

const countSchema = z.object({
  object: z.literal('response.input_tokens'),
  input_tokens: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
});
const usageSchema = z.object({
  input_tokens: z.number().int().nonnegative().max(maximumInputTokens),
  output_tokens: z.number().int().nonnegative().max(maximumOutputTokens),
  input_tokens_details: z.object({ cached_tokens: z.number().int().nonnegative() }),
});

export type AnalysisUsage = {
  inputTokens: number;
  cachedTokens: number;
  outputTokens: number;
  costMicros: number;
};

export class OpenAiRequestError extends ApiError {
  readonly chargeUncertain: boolean;

  constructor(code: string, message: string, chargeUncertain: boolean) {
    super(502, code, message);
    this.chargeUncertain = chargeUncertain;
  }
}

export function analysisCostMicros(input: number, output: number, cached = 0): number {
  if (
    !Number.isSafeInteger(input) || input < 0 || input > maximumInputTokens ||
    !Number.isSafeInteger(output) || output < 0 || output > maximumOutputTokens ||
    !Number.isSafeInteger(cached) || cached < 0 || cached > input
  ) {
    throw new OpenAiRequestError('OPENAI_USAGE_INVALID', 'OpenAI zwróciło nieprawidłowe zużycie tokenów.', true);
  }
  // Standard snapshot pricing, rounded up to a microdollar; cached input is discounted.
  return Math.ceil(((input - cached) * 30 + cached * 3 + output * 180) / 40);
}

export function buildAnalysisRequest(options: {
  instructions: string;
  input: AnalysisInput[];
  schema: Record<string, unknown>;
  name: string;
}): AnalysisRequest {
  if (!options.instructions.trim() || !options.input.length || !/^[a-z][a-z0-9_]{0,63}$/.test(options.name)) {
    throw new ApiError(400, 'AI_INPUT_REQUIRED', 'Analiza wymaga opisu, materiałów i poprawnego formatu wyniku.');
  }
  return {
    model: analysisModel,
    instructions: options.instructions,
    input: [{ role: 'user', content: options.input }],
    reasoning: { effort: 'medium' },
    text: { format: { type: 'json_schema', name: options.name, strict: true, schema: options.schema } },
  };
}

async function post(
  path: '/responses/input_tokens' | '/responses',
  options: {
    key: string;
    body: Record<string, unknown>;
    fetcher: typeof fetch;
    signal?: AbortSignal;
  },
): Promise<unknown> {
  if (!options.key.trim()) throw new ApiError(503, 'OPENAI_NOT_CONFIGURED', 'Nie skonfigurowano OpenAI.');
  const signal = AbortSignal.timeout(path === '/responses' ? 180_000 : 60_000);
  let response: Response;
  try {
    response = await options.fetcher(`https://api.openai.com/v1${path}`, {
      method: 'POST',
      headers: { authorization: `Bearer ${options.key}`, 'content-type': 'application/json' },
      body: JSON.stringify(options.body),
      signal: options.signal ? AbortSignal.any([options.signal, signal]) : signal,
      redirect: 'error',
    });
  } catch (error) {
    if (error instanceof TypeError || (error instanceof DOMException && ['TimeoutError', 'AbortError'].includes(error.name))) {
      throw new OpenAiRequestError('OPENAI_UNAVAILABLE', 'Nie potwierdzono odpowiedzi OpenAI. Nie ponawiamy płatnego wywołania automatycznie.', path === '/responses');
    }
    throw error;
  }
  if (!response.ok) {
    const code = response.status === 401 ? 'OPENAI_AUTHENTICATION_FAILED'
      : response.status === 429 ? 'OPENAI_RATE_LIMITED' : 'OPENAI_REQUEST_REJECTED';
    const rejectedBeforeGeneration = [400, 401, 403, 404, 413, 415, 422, 429].includes(response.status);
    throw new OpenAiRequestError(code, `OpenAI odrzuciło żądanie (HTTP ${response.status}).`, path === '/responses' && !rejectedBeforeGeneration);
  }
  const reader = response.body?.getReader();
  if (!reader) throw new OpenAiRequestError('OPENAI_RESPONSE_INVALID', 'OpenAI nie zwróciło danych odpowiedzi.', path === '/responses');
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.length;
      if (size > 2 * 1024 * 1024) {
        await reader.cancel();
        throw new OpenAiRequestError('OPENAI_RESPONSE_INVALID', 'Odpowiedź OpenAI przekroczyła limit rozmiaru.', path === '/responses');
      }
      chunks.push(next.value);
    }
  } catch (error) {
    if (error instanceof OpenAiRequestError) throw error;
    if (error instanceof TypeError || (error instanceof DOMException && ['TimeoutError', 'AbortError'].includes(error.name))) {
      throw new OpenAiRequestError('OPENAI_UNAVAILABLE', 'Nie odebrano kompletnej odpowiedzi OpenAI.', path === '/responses');
    }
    throw error;
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch (error) {
    if (error instanceof SyntaxError) throw new OpenAiRequestError('OPENAI_RESPONSE_INVALID', 'OpenAI zwróciło nieprawidłowy JSON.', path === '/responses');
    throw error;
  }
}

export async function countAnalysisInput(options: {
  key: string; request: AnalysisRequest; fetcher?: typeof fetch; signal?: AbortSignal;
}): Promise<{ tokens: number; maximumCostMicros: number }> {
  const raw = await post('/responses/input_tokens', {
    key: options.key, body: options.request, fetcher: options.fetcher ?? fetch, signal: options.signal,
  });
  const count = countSchema.safeParse(raw);
  if (!count.success) throw new OpenAiRequestError('OPENAI_RESPONSE_INVALID', 'OpenAI nie potwierdziło liczby tokenów.', false);
  if (count.data.input_tokens > maximumInputTokens) {
    throw new ApiError(413, 'AI_INPUT_TOO_LARGE', 'Materiały przekraczają okno kontekstu modelu. Zmniejsz zakres analizy.');
  }
  const maximumCostMicros = analysisCostMicros(count.data.input_tokens, maximumOutputTokens);
  if (maximumCostMicros > maximumAnalysisCostMicros) {
    throw new ApiError(409, 'AI_ANALYSIS_BUDGET_EXCEEDED', 'Analiza przekracza zatwierdzony limit kosztu.');
  }
  return { tokens: count.data.input_tokens, maximumCostMicros };
}

export async function generateAnalysis(options: {
  key: string; request: AnalysisRequest; fetcher?: typeof fetch; signal?: AbortSignal;
}): Promise<unknown> {
  return post('/responses', {
    key: options.key,
    body: { ...options.request, store: false, max_output_tokens: maximumOutputTokens, truncation: 'disabled' },
    fetcher: options.fetcher ?? fetch,
    signal: options.signal,
  });
}

export function parseAnalysisUsage(value: unknown): AnalysisUsage {
  const envelope = z.object({ model: z.literal(analysisModel), usage: usageSchema }).safeParse(value);
  if (!envelope.success) throw new OpenAiRequestError('OPENAI_USAGE_INVALID', 'Nie potwierdzono modelu i rozliczenia analizy.', true);
  const usage = envelope.data.usage;
  const cached = usage.input_tokens_details.cached_tokens;
  return {
    inputTokens: usage.input_tokens, outputTokens: usage.output_tokens, cachedTokens: cached,
    costMicros: analysisCostMicros(usage.input_tokens, usage.output_tokens, cached),
  };
}

export function parseAnalysisResult<T>(value: unknown, schema: z.ZodType<T>): T {
  const envelope = z.object({
    id: z.string().min(1), model: z.literal(analysisModel), status: z.literal('completed'),
    output: z.array(z.discriminatedUnion('type', [
      z.object({ type: z.literal('reasoning') }),
      z.object({
        type: z.literal('message'), role: z.literal('assistant'), status: z.literal('completed'),
        content: z.array(z.object({ type: z.literal('output_text'), text: z.string() })).min(1),
      }),
    ])),
  }).safeParse(value);
  if (!envelope.success) throw new ApiError(502, 'OPENAI_RESULT_INVALID', 'Analiza nie została ukończona lub model odmówił odpowiedzi. Nie zmieniono zadań.');
  const messages = envelope.data.output.filter((item) => item.type === 'message');
  if (messages.length !== 1) throw new ApiError(502, 'OPENAI_RESULT_INVALID', 'Nie potwierdzono jednoznacznego wyniku analizy.');
  let result: unknown;
  try {
    result = JSON.parse(messages[0].content.map((part) => part.text).join(''));
  } catch (error) {
    if (error instanceof SyntaxError) throw new ApiError(502, 'OPENAI_RESULT_INVALID', 'Wynik analizy nie jest poprawnym JSON-em.');
    throw error;
  }
  const parsed = schema.safeParse(result);
  if (!parsed.success) throw new ApiError(502, 'OPENAI_RESULT_INVALID', 'Wynik analizy nie spełnia wymaganego formatu.');
  return parsed.data;
}
