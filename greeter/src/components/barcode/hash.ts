import { HASH } from '../../config/constants';

/** FNV-1a hash — turns a string into a sequence of pseudo-random bytes. */
export function hashBytes(input: string): number[] {
  const bytes: number[] = [];
  let h: number = HASH.FNV_OFFSET_BASIS;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, HASH.FNV_PRIME);
  }
  for (let i = 0; i < HASH.BYTE_COUNT; i++) {
    h ^= i;
    h = Math.imul(h, HASH.FNV_PRIME);
    bytes.push((h >>> 0) & 0xff);
  }
  return bytes;
}

export function toHex(bytes: number[], count: number): string {
  return bytes
    .slice(0, count)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase();
}
