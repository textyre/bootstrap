const DAYS = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday',
  'Thursday', 'Friday', 'Saturday',
];

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

function pad(n: number): string {
  return n.toString().padStart(2, '0');
}

function update(): void {
  const now = new Date();

  const clockEl = document.getElementById('clock');
  const dateEl = document.getElementById('date');

  if (clockEl) {
    clockEl.textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  }

  if (dateEl) {
    const day = DAYS[now.getDay()];
    const date = now.getDate();
    const month = MONTHS[now.getMonth()];
    dateEl.textContent = `${day} ${date} ${month}`;
  }
}

export function initClock(): void {
  update();
  setInterval(update, 1000);
}
