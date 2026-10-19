import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const SALT_BYTES = 16;
const KEY_BYTES = 64;
const COST = 32_768;
const BLOCK_SIZE = 8;
const PARALLELISM = 1;
const MAX_MEMORY = 64 * 1024 * 1024;

export const dummyPasswordHash = `$scrypt$v1$${COST}$${BLOCK_SIZE}$${PARALLELISM}$${Buffer.alloc(SALT_BYTES).toString('base64url')}$${Buffer.alloc(KEY_BYTES).toString('base64url')}`;

function deriveKey(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, KEY_BYTES, {
      N: COST,
      r: BLOCK_SIZE,
      p: PARALLELISM,
      maxmem: MAX_MEMORY,
    }, (error, key) => {
      if (error) {
        reject(error);
      } else {
        resolve(key as Buffer);
      }
    });
  });
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(SALT_BYTES);
  const derivedKey = await deriveKey(password, salt);

  return `$scrypt$v1$${COST}$${BLOCK_SIZE}$${PARALLELISM}$${salt.toString('base64url')}$${derivedKey.toString('base64url')}`;
}

export async function verifyPassword(password: string, passwordHash: string): Promise<boolean> {
  const match = /^\$scrypt\$v1\$(\d+)\$(\d+)\$(\d+)\$([A-Za-z0-9_-]+)\$([A-Za-z0-9_-]+)$/.exec(passwordHash);

  if (!match || Number(match[1]) !== COST || Number(match[2]) !== BLOCK_SIZE || Number(match[3]) !== PARALLELISM) {
    return false;
  }

  const salt = Buffer.from(match[4], 'base64url');
  const expectedKey = Buffer.from(match[5], 'base64url');

  if (salt.length !== SALT_BYTES || expectedKey.length !== KEY_BYTES) {
    return false;
  }

  const actualKey = await deriveKey(password, salt);
  return timingSafeEqual(actualKey, expectedKey);
}