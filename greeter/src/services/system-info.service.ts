import type { SystemInfo } from '../types/global';
import { DEFAULT_SYSTEM_INFO } from '../config/messages';

let cached: SystemInfo | null = null;

export async function loadSystemInfo(): Promise<SystemInfo> {
  if (cached) return cached;

  try {
    const resp = await fetch('./system-info.json');
    cached = await resp.json();
    return cached!;
  } catch {
    cached = { ...DEFAULT_SYSTEM_INFO };
    return cached;
  }
}
