import type { AnimationPhase, AnimationStep } from '../types/animation.types';
import { CSS_CLASSES } from '../config/selectors';
import { delay } from '../utils/delay';
import { awaitAnimation, trigger } from './animation-utils';
import { BOOT_PHASES } from './animation-phases';

function applyStep(el: Element, step: AnimationStep): void {
  if (step.removeClasses) {
    step.removeClasses.forEach((c) => el.classList.remove(c));
  }

  if (step.useTrigger === false) {
    el.classList.add(step.triggerClass);
  } else {
    trigger(el, step.triggerClass);
  }
}

async function runPhase(phase: AnimationPhase): Promise<void> {
  if (phase.preDelay) {
    await delay(phase.preDelay);
  }

  // Start parallel steps at their specified delay offset
  let parallelPromise = Promise.resolve();
  if (phase.parallel) {
    const { delay: parallelDelay, steps } = phase.parallel;
    parallelPromise = delay(parallelDelay).then(() => {
      for (const step of steps) {
        const el = document.querySelector(step.selector) as HTMLElement | null;
        if (!el) continue;
        applyStep(el, step);
      }
    });
  }

  // Fire ALL sequential step triggers synchronously, then await the waitForAnimation step
  let animationTarget: Element | null = null;

  for (const step of phase.steps) {
    const el = document.querySelector(step.selector) as HTMLElement | null;
    if (!el) continue;

    applyStep(el, step);

    if (step.waitForAnimation) {
      animationTarget = el;
    }
  }

  // Wait for the designated animation to complete
  if (animationTarget) {
    await awaitAnimation(animationTarget);
  }

  // Ensure parallel work is done
  await parallelPromise;

  if (phase.postDelay) {
    await delay(phase.postDelay);
  }
}

export async function runBootAnimation(): Promise<void> {
  // Reduced motion — show everything immediately
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.querySelectorAll('.' + CSS_CLASSES.BOOT_PRE).forEach((el) => {
      el.classList.remove(CSS_CLASSES.BOOT_PRE);
    });
    return;
  }

  for (const phase of BOOT_PHASES) {
    await runPhase(phase);
  }
}
