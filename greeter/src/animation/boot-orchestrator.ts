import { animate } from 'motion';
import { CSS_CLASSES } from '../config/selectors';
import { delay } from '../utils/delay';
import {
  buildBootSequence,
  BOOT_ANIMATED_SELECTORS,
  BOOT_SETTLE_DELAY_S,
} from './animation-phases';

/**
 * Orchestrates the boot animation sequence using Motion.
 * Handles reduced-motion preference by showing all elements immediately.
 */
export class BootAnimator {
  async run(): Promise<void> {
    // Reduced motion -- show everything immediately
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      this.showAll();
      return;
    }

    // Remove boot-pre so elements are visible (opacity controlled by animation keyframes)
    this.revealBootElements();

    // Build and run the full boot animation sequence
    const sequence = buildBootSequence();
    const controls = animate(sequence);

    // Wait for entire sequence to finish
    await controls.finished;

    // Final settle delay
    await delay(BOOT_SETTLE_DELAY_S * 1000);
  }

  /**
   * Show all hidden elements immediately (reduced-motion path).
   */
  private showAll(): void {
    document.querySelectorAll('.' + CSS_CLASSES.BOOT_PRE).forEach((el) => {
      el.classList.remove(CSS_CLASSES.BOOT_PRE);
    });
  }

  /**
   * Remove the `.boot-pre` hidden-state class from all animated elements
   * so Motion can animate them from their initial keyframe values.
   */
  private revealBootElements(): void {
    for (const selector of BOOT_ANIMATED_SELECTORS) {
      document.querySelectorAll(selector).forEach((el) => {
        el.classList.remove(CSS_CLASSES.BOOT_PRE);
      });
    }
  }
}
