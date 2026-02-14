import type { SystemInfo } from '../types/global';
import { DEFAULT_SYSTEM_INFO } from '../config/system-info.defaults';
import { logError } from '../utils/logger';

export class SystemInfoService {
  private cached: SystemInfo | null = null;

  async load(): Promise<SystemInfo> {
    if (this.cached) return this.cached;

    try {
      const resp = await fetch('./system-info.json');
      this.cached = await resp.json();
      return this.cached!;
    } catch (err) {
      logError('system-info:fetch', err);
      this.cached = { ...DEFAULT_SYSTEM_INFO };
      return this.cached;
    }
  }
}
