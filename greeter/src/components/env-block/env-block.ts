import type { SystemInfo } from '../../types/global';
import { SELECTORS } from '../../config/selectors';

export class EnvBlock {
  private readonly envEl: HTMLElement | null;
  private readonly ipEl: HTMLElement | null;
  private readonly projectEl: HTMLElement | null;
  private readonly kernelEl: HTMLElement | null;

  constructor() {
    this.envEl = document.querySelector(SELECTORS.ENV_VALUE);
    this.ipEl = document.querySelector(SELECTORS.IP_VALUE);
    this.projectEl = document.querySelector(SELECTORS.VERSION_PROJECT);
    this.kernelEl = document.querySelector(SELECTORS.VERSION_KERNEL);
  }

  render(info: SystemInfo): void {
    if (this.envEl) this.envEl.textContent = info.virtualization_type;
    if (this.ipEl) this.ipEl.textContent = info.ip_address;
    if (this.projectEl) this.projectEl.textContent = `ctos-${info.project_version}`;
    if (this.kernelEl) this.kernelEl.textContent = info.kernel;
  }
}
