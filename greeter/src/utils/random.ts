import { SCRAMBLE_CHARS } from '../config/constants';

export function randomString(length: number): string {
  let s = '';
  for (let i = 0; i < length; i++) {
    s += SCRAMBLE_CHARS[Math.floor(Math.random() * SCRAMBLE_CHARS.length)];
  }
  return s;
}
