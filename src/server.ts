import 'dotenv/config';
import { parseConfig } from './config.ts';
import { createApp } from './app.ts';
import { prisma } from './db/prisma.ts';

const config = parseConfig();
const app = createApp({ prisma, config });

try {
  await app.listen({ port: config.PORT, host: config.HOST });
} catch (error) {
  app.log.error({ err: error }, 'API failed to start');
  await app.close();
  process.exitCode = 1;
}