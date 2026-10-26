import { CopilotClient, RuntimeConnection } from '@github/copilot-sdk';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { z } from 'zod';
import type { Prisma } from '../../src/generated/prisma/client.ts';

const snapshotSchema = z.object({
  isUnlimitedEntitlement: z.boolean(),
  entitlementRequests: z.number().min(-1).max(Number.MAX_SAFE_INTEGER),
  usedRequests: z.number().nonnegative().max(Number.MAX_SAFE_INTEGER),
  usageAllowedWithExhaustedQuota: z.boolean(),
  remainingPercentage: z.number(),
  overage: z.number().nonnegative().max(Number.MAX_SAFE_INTEGER),
  overageAllowedWithExhaustedQuota: z.boolean(),
  resetDate: z.string().min(1).optional(),
});
export const quotaSchema = z.object({
  quotaSnapshots: z.record(z.string().min(1).max(100), snapshotSchema),
});

export function metadataJson(value: unknown): Prisma.InputJsonObject {
  const json = z.record(z.string(), z.json()).parse(value);
  if (Buffer.byteLength(JSON.stringify(json), 'utf8') > 1024 * 1024) throw new Error('SDK metadata exceeded its safety limit.');
  return json;
}

export async function discoverAccountMetadata(
  token: string, parentSignal?: AbortSignal,
): Promise<{ catalog: Prisma.InputJsonObject; quota: Prisma.InputJsonObject }> {
  if (token.length < 20 || /[\r\n]/.test(token)) throw new Error('Invalid SDK account credential.');
  const signal = parentSignal ? AbortSignal.any([parentSignal, AbortSignal.timeout(90_000)]) : AbortSignal.timeout(90_000);
  signal.throwIfAborted();
  const home = await mkdtemp(join(tmpdir(), 'ccc-sdk-metadata-'));
  let client: CopilotClient | undefined;
  let result: { catalog: Prisma.InputJsonObject; quota: Prisma.InputJsonObject } | undefined;
  let failure: unknown;
  let abort: (() => void) | undefined;
  let pending: Promise<void> | undefined;
  try {
    const workingDirectory = join(home, 'runtime');
    await mkdir(workingDirectory, { mode: 0o700 });
    client = new CopilotClient({
      mode: 'empty', connection: RuntimeConnection.forStdio(),
      baseDirectory: join(home, 'state'), workingDirectory,
      useLoggedInUser: false, gitHubToken: token,
      env: { PATH: '/usr/local/bin:/usr/bin:/bin', HOME: home, TMPDIR: home },
      logLevel: 'none',
    });
    const selected = client;
    const cancelled = new Promise<never>((_resolve, reject) => {
      abort = () => reject(new Error('SDK metadata refresh was interrupted or timed out.'));
      if (signal.aborted) abort();
      else signal.addEventListener('abort', abort, { once: true });
    });
    pending = (async () => {
      await selected.start();
      // Empty mode has no current account; every read is scoped explicitly.
      const { models } = await selected.rpc.models.list({ gitHubToken: token });
      if (!models.length || models.length > 200) throw new Error('Copilot returned an invalid model catalog.');
      const priceUnits = await selected.rpc.models.listTokenPriceUnits({ gitHubToken: token });
      const quota = quotaSchema.parse(await selected.rpc.account.getQuota({ gitHubToken: token }));
      if (Object.keys(quota.quotaSnapshots).length > 20) throw new Error('Copilot returned too many quota types.');
      result = {
        catalog: metadataJson({
          readOnly: true, sessionsCreated: 0, authentication: 'explicit-token-rpc', priceUnits,
          models: models.map((model) => ({
            id: model.id, name: model.name, policy: model.policy?.state ?? null,
            multiplier: model.billing?.multiplier ?? null, tokenPrices: model.billing?.tokenPrices ?? null,
            reasoningEfforts: model.supportedReasoningEfforts ?? [],
          })),
        }),
        quota: metadataJson(quota),
      };
    })();
    await Promise.race([pending, cancelled]);
  } catch (error) {
    failure = error;
  } finally {
    if (abort) signal.removeEventListener('abort', abort);
    const errors: unknown[] = [];
    if (client) {
      try { errors.push(...await client.stop()); } catch (error) { errors.push(error); }
    }
    if (pending) await Promise.allSettled([pending]);
    try { await rm(home, { recursive: true, force: true }); } catch (error) { errors.push(error); }
    if (errors.length) failure = new AggregateError([...(failure ? [failure] : []), ...errors], 'SDK metadata cleanup failed.');
  }
  if (failure) throw failure;
  if (!result) throw new Error('No authenticated SDK metadata returned.');
  return result;
}
