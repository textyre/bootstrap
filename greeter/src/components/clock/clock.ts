import { TIMINGS } from '../../config/timings';
import { SELECTORS } from '../../config/selectors';

export class Clock {
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private readonly clockEl: HTMLElement | null;
  private readonly dateEl: HTMLElement | null;
  private readonly timeFmt: Intl.DateTimeFormat;
  private readonly dayFmt: Intl.DateTimeFormat;
  private readonly dateFmt: Intl.DateTimeFormat;
  private readonly monthFmt: Intl.DateTimeFormat;

  constructor() {
    this.clockEl = document.querySelector(SELECTORS.CLOCK);
    this.dateEl = document.querySelector(SELECTORS.DATE);
    this.timeFmt = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false });
    this.dayFmt = new Intl.DateTimeFormat('en-GB', { weekday: 'long' });
    this.dateFmt = new Intl.DateTimeFormat('en-GB', { day: 'numeric' });
    this.monthFmt = new Intl.DateTimeFormat('en-GB', { month: 'long' });
  }

  start(): void {
    this.update();
    this.intervalId = setInterval(() => this.update(), TIMINGS.CLOCK_TICK);
  }

  stop(): void {
    if (this.intervalId !== null) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  private update(): void {
    const now = new Date();

    if (this.clockEl) {
      this.clockEl.textContent = this.timeFmt.format(now);
    }

    if (this.dateEl) {
      this.dateEl.textContent = `${this.dayFmt.format(now)} ${this.dateFmt.format(now)} ${this.monthFmt.format(now)}`;
    }
  }
}
