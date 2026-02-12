import { TIMING, CLOCK } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';

export interface ClockController {
  start(): void;
  stop(): void;
}

function pad(n: number): string {
  return n.toString().padStart(2, '0');
}

export function createClock(): ClockController {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  function update(): void {
    const now = new Date();

    const clockEl = document.getElementById(SELECTORS.CLOCK);
    const dateEl = document.getElementById(SELECTORS.DATE);

    if (clockEl) {
      clockEl.textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
    }

    if (dateEl) {
      const day = CLOCK.DAYS[now.getDay()];
      const date = now.getDate();
      const month = CLOCK.MONTHS[now.getMonth()];
      dateEl.textContent = `${day} ${date} ${month}`;
    }
  }

  return {
    start() {
      update();
      intervalId = setInterval(update, TIMING.CLOCK_TICK);
    },
    stop() {
      if (intervalId !== null) {
        clearInterval(intervalId);
        intervalId = null;
      }
    },
  };
}
