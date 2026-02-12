import type { AnimationPhase } from '../types/animation.types';
import { TIMING } from '../config/constants';
import { SELECTORS, CSS_CLASSES } from '../config/selectors';

const sel = (id: string): string => '#' + id;

export const BOOT_PHASES: AnimationPhase[] = [
  {
    name: 'logo-load',
    preDelay: TIMING.BOOT_INITIAL_DELAY,
    steps: [
      { selector: sel(SELECTORS.CTOS_BLOCK), triggerClass: CSS_CLASSES.BOOT_LOADING, waitForAnimation: true },
      { selector: sel(SELECTORS.LICENSE), triggerClass: CSS_CLASSES.BOOT_ENTER },
    ],
    parallel: {
      delay: TIMING.PERIPHERAL_DELAY,
      steps: [
        { selector: sel(SELECTORS.RIGHT_EDGE), triggerClass: CSS_CLASSES.BOOT_FLICKER },
        { selector: sel(SELECTORS.SECURITY_META), triggerClass: CSS_CLASSES.BOOT_SLIDE },
        { selector: sel(SELECTORS.ARCH_LOGO), triggerClass: CSS_CLASSES.BOOT_ENTER },
        { selector: sel(SELECTORS.CLOCK), triggerClass: CSS_CLASSES.BOOT_ENTER },
        { selector: sel(SELECTORS.DATE_BOX), triggerClass: CSS_CLASSES.BOOT_ENTER },
        { selector: sel(SELECTORS.ENV_BLOCK), triggerClass: CSS_CLASSES.BOOT_EXPAND },
      ],
    },
  },
  {
    name: 'pullback',
    preDelay: TIMING.PHASE_GAP,
    steps: [
      {
        selector: sel(SELECTORS.CTOS_BLOCK),
        triggerClass: CSS_CLASSES.BOOT_PULLBACK,
        useTrigger: false,
        removeClasses: [CSS_CLASSES.BOOT_LOADING],
        waitForAnimation: true,
      },
      { selector: '.' + CSS_CLASSES.OS, triggerClass: CSS_CLASSES.BOOT_REVEAL },
    ],
  },
  {
    name: 'form-reveal',
    steps: [
      { selector: sel(SELECTORS.CTOS_LOGO), triggerClass: CSS_CLASSES.BOOT_SHIFT_UP },
      { selector: '.' + CSS_CLASSES.FORM_CONTAINER, triggerClass: CSS_CLASSES.BOOT_ENTER, waitForAnimation: true },
    ],
    postDelay: TIMING.FINAL_SETTLE,
  },
];
