import { CSS_CLASSES } from '../config/selectors';

export function awaitAnimation(el: Element): Promise<void> {
  return new Promise((resolve) => {
    el.addEventListener('animationend', () => resolve(), { once: true });
  });
}

export function trigger(el: Element, triggerClass: string): void {
  el.classList.remove(CSS_CLASSES.BOOT_PRE);
  el.classList.add(triggerClass);
}
