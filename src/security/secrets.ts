import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

export function createRandomToken(size = 32): string {
  return randomBytes(size).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

function encryptionKey(value: string): Buffer {
  const key = Buffer.from(value, 'base64url');

  if (key.length !== 32) {
    throw new Error('APP_ENCRYPTION_KEY must be a base64url-encoded 32-byte key.');
  }

  return key;
}

export function encryptSecret(value: string, keyValue: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(keyValue), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();

  return `v1.${iv.toString('base64url')}.${tag.toString('base64url')}.${ciphertext.toString('base64url')}`;
}

export function decryptSecret(encrypted: string, keyValue: string): string {
  const [version, encodedIv, encodedTag, encodedCiphertext, ...rest] = encrypted.split('.');

  if (version !== 'v1' || !encodedIv || !encodedTag || !encodedCiphertext || rest.length > 0) {
    throw new Error('Encrypted value has an invalid format.');
  }

  const decipher = createDecipheriv(
    'aes-256-gcm',
    encryptionKey(keyValue),
    Buffer.from(encodedIv, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(encodedTag, 'base64url'));

  return Buffer.concat([
    decipher.update(Buffer.from(encodedCiphertext, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}