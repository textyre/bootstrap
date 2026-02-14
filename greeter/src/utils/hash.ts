/** SHA-256 hash — turns a string into a sequence of bytes via Web Crypto API. */
export async function hashBytes(input: string): Promise<number[]> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer));
}

export function toHex(bytes: number[], count: number): string {
  return bytes
    .slice(0, count)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase();
}
