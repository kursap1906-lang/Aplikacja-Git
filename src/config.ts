import { z } from 'zod';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.url(),
  APP_ORIGIN: z.url().default('http://127.0.0.1:3000'),
  PUBLIC_API_URL: z.url().default('http://127.0.0.1:3000'),
  EDITOR_URL: z.url().refine((value) => new URL(value).protocol === 'https:').optional(),
  GITHUB_CLIENT_ID: z.string().min(1).optional(),
  GITHUB_CLIENT_SECRET: z.string().min(1).optional(),
  GITHUB_WEBHOOK_SECRET: z.string().min(32).optional(),
  APP_ENCRYPTION_KEY: z.string().optional(),
}).superRefine((config, context) => {
  if (!config.EDITOR_URL || config.NODE_ENV !== 'production') {
    return;
  }

  const appHost = new URL(config.APP_ORIGIN).hostname;
  const editor = new URL(config.EDITOR_URL);
  if (editor.hostname !== `editor.${appHost}` || !editor.pathname.startsWith('/editor')) {
    context.addIssue({
      code: 'custom',
      path: ['EDITOR_URL'],
      message: 'Production editor URL must use the editor subdomain and /editor path.',
    });
  }
});

export type AppConfig = z.infer<typeof configSchema>;

export function parseConfig(environment: NodeJS.ProcessEnv = process.env): AppConfig {
  return configSchema.parse(environment);
}