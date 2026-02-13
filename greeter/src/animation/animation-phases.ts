import type { AnimationSequence } from 'motion';
import { steps } from 'motion-utils';
import { TIMING } from '../config/constants';
import { SELECTORS } from '../config/selectors';

/* eslint-disable @typescript-eslint/naming-convention */

/** Easing curves matching CSS custom properties */
const EASE_DECEL: [number, number, number, number] = [0.16, 1, 0.3, 1];
const EASE_LOADER: [number, number, number, number] = [0.11, 0, 0.5, 0];

/**
 * Lamp-flicker opacity keyframes (step-end timing from CSS).
 * Each value is a discrete opacity step matching the original CSS percentages.
 */
const FLICKER_TIMES = [
  0, 0.05, 0.08, 0.15, 0.18, 0.22, 0.30, 0.33,
  0.40, 0.42, 0.50, 0.55, 0.60, 0.65, 0.72, 0.76,
  0.82, 0.88, 0.94, 1.0,
];
const FLICKER_OPACITIES = [
  0, 0.7, 0, 0.9, 0.1, 0, 0.8, 0,
  0.6, 0, 0.9, 0.3, 0.8, 0, 1, 0.4,
  1, 0.6, 1, 1,
];

/** Step-end easing array: one step(1, 'end') per keyframe interval */
const FLICKER_EASE = Array.from(
  { length: FLICKER_OPACITIES.length - 1 },
  () => steps(1, 'end'),
);

/**
 * Env-expand clip-path keyframes matching the original 4-step CSS animation.
 * 0%   -> collapsed point (hidden)
 * 5%   -> collapsed point (visible)
 * 20%  -> vertical line
 * 52%  -> vertical line hold
 * 100% -> fully expanded
 */
const ENV_CLIP_PATHS = [
  'inset(calc(50% - 1px) calc(50% - 1px) calc(50% - 1px) calc(50% - 1px))',
  'inset(calc(50% - 1px) calc(50% - 1px) calc(50% - 1px) calc(50% - 1px))',
  'inset(0% calc(50% - 1px) 0% calc(50% - 1px))',
  'inset(0% calc(50% - 1px) 0% calc(50% - 1px))',
  'inset(0% 0% 0% 0%)',
];
const ENV_CLIP_TIMES = [0, 0.05, 0.20, 0.52, 1.0];
const ENV_OPACITIES = [0, 1, 1, 1, 1];

// ---- Timing constants (seconds for Motion API) ----

const INITIAL_DELAY_S = TIMING.BOOT_INITIAL_DELAY / 1000;
const PERIPHERAL_OFFSET_S = TIMING.PERIPHERAL_DELAY / 1000;
const PHASE_GAP_S = TIMING.PHASE_GAP / 1000;
const FINAL_SETTLE_S = TIMING.FINAL_SETTLE / 1000;

// Duration values (seconds)
const LOADER_DUR = 1.8;
const PULLBACK_DUR = 0.7;
const FADE_DUR = 0.6;
const SHIFT_DUR = 1.0;
const FORM_DUR = 1.0;
const ARCH_DUR = 3.0;
const ENV_DUR = 0.8;
const PREFIX_FADE_DUR = 0.3;
const BOTTOM_FADE_DUR = 0.4;

// Delay values (seconds, relative to peripheral group start)
const FLICKER_DLY = 1.0;
const META_DLY = 1.3;
const CLOCK_DLY = 0.8;
const DATE_DLY = 0.85;
const ARCH_DLY = 0.8;
const ENV_DLY = 0.6;
const ENV_TEXT_DLY = 1.0;
const LICENSE_DLY = 3.0;
const PREFIX_FADE_DLY = 0.3;

// SELECTORS already include the '.' prefix (class selectors), so use them directly.
const S_CTOS_BLOCK = SELECTORS.CTOS_BLOCK;
const S_CTOS_LOGO = SELECTORS.CTOS_LOGO;
const S_LICENSE = SELECTORS.LICENSE;
const S_RIGHT_EDGE = SELECTORS.RIGHT_EDGE;
const S_SECURITY_META = SELECTORS.SECURITY_META;
const S_ARCH_LOGO = SELECTORS.ARCH_LOGO;
const S_CLOCK = SELECTORS.CLOCK;
const S_DATE_BOX = SELECTORS.DATE_BOX;
const S_ENV_BLOCK = SELECTORS.ENV_BLOCK;
const S_OS_PREFIX = SELECTORS.OS_PREFIX;

/**
 * All selectors whose `.boot-pre` class must be removed before animating.
 */
export const BOOT_ANIMATED_SELECTORS: readonly string[] = [
  S_CTOS_BLOCK,
  S_LICENSE,
  S_RIGHT_EDGE,
  S_SECURITY_META,
  S_ARCH_LOGO,
  S_CLOCK,
  S_DATE_BOX,
  S_ENV_BLOCK,
  '.form-container',
  '.os',
  S_OS_PREFIX,
];

/**
 * Builds the full boot animation sequence for Motion's `animate()`.
 *
 * The sequence is structured in 3 phases matching the original boot animation:
 *   Phase 1 - logo-load: CTOS block clip-path reveal + peripheral elements
 *   Phase 2 - pullback: CTOS block width shrink + OS text reveal
 *   Phase 3 - form-reveal: Logo shifts up + form slides in
 */
export function buildBootSequence(): AnimationSequence {
  const p1 = INITIAL_DELAY_S;
  const periph = p1 + PERIPHERAL_OFFSET_S;
  const p2 = p1 + LOADER_DUR + PHASE_GAP_S;
  const p3 = p2 + PULLBACK_DUR;

  return [
    // ===== Phase 1: Logo load =====

    // CTOS block clip-path expand (the main loader bar)
    [
      S_CTOS_BLOCK,
      { clipPath: ['inset(0 100% 0 0)', 'inset(0 0% 0 0)'] },
      { duration: LOADER_DUR, ease: EASE_LOADER },
    ],

    // License fade-in (concurrent, with long delay)
    [
      S_LICENSE,
      { opacity: [0, 1] },
      { duration: FADE_DUR, ease: 'easeOut' as const, at: p1 + LICENSE_DLY },
    ],

    // Right-edge lamp flicker (step-end: hold each value until next keyframe)
    [
      S_RIGHT_EDGE,
      { opacity: FLICKER_OPACITIES },
      {
        duration: FADE_DUR,
        ease: FLICKER_EASE,
        times: FLICKER_TIMES,
        at: periph + FLICKER_DLY,
      },
    ],

    // Security meta slide-in from right
    [
      S_SECURITY_META,
      { opacity: [0, 1], transform: ['translateX(100%)', 'translateX(0)'] },
      { duration: FADE_DUR, ease: EASE_DECEL, at: periph + META_DLY },
    ],

    // Arch logo scale-in
    [
      S_ARCH_LOGO,
      { opacity: [0, 1], transform: ['scale(0.5)', 'scale(1)'] },
      { duration: ARCH_DUR, ease: EASE_DECEL, at: periph + ARCH_DLY },
    ],

    // Clock fade from top
    [
      S_CLOCK,
      { opacity: [0, 1], transform: ['translateY(-20px)', 'translateY(0)'] },
      { duration: SHIFT_DUR, ease: EASE_DECEL, at: periph + CLOCK_DLY },
    ],

    // Date box fade from top (staggered after clock)
    [
      S_DATE_BOX,
      { opacity: [0, 1], transform: ['translateY(-20px)', 'translateY(0)'] },
      { duration: SHIFT_DUR, ease: EASE_DECEL, at: periph + DATE_DLY },
    ],

    // Env block 4-phase reveal (clip-path expansion)
    [
      S_ENV_BLOCK,
      { clipPath: ENV_CLIP_PATHS, opacity: ENV_OPACITIES },
      {
        duration: ENV_DUR,
        ease: 'linear' as const,
        times: ENV_CLIP_TIMES,
        at: periph + ENV_DLY,
      },
    ],

    // Env block inner text fade-in
    [
      S_ENV_BLOCK + ' .info-col',
      { opacity: [0, 1] },
      { duration: PREFIX_FADE_DUR, ease: 'easeOut' as const, at: periph + ENV_TEXT_DLY },
    ],

    // ===== Phase 2: Pullback =====

    // CTOS block width shrink
    [
      S_CTOS_BLOCK,
      { width: ['250px', '170px'] },
      { duration: PULLBACK_DUR, ease: EASE_DECEL, at: p2 },
    ],

    // OS prefix fade-in (inside ctos-block during pullback)
    [
      S_OS_PREFIX,
      { opacity: [0, 1] },
      { duration: PREFIX_FADE_DUR, ease: 'easeOut' as const, at: p2 + PREFIX_FADE_DLY },
    ],

    // OS text reveal
    [
      '.os',
      { opacity: [0, 1] },
      { duration: FADE_DUR, ease: 'easeOut' as const, at: p2 },
    ],

    // ===== Phase 3: Form reveal =====

    // Logo shifts up (fill: forwards prevents backwards fill hiding logo during phases 1-2)
    [
      S_CTOS_LOGO,
      { transform: ['translateY(100%)', 'translateY(0)'] },
      { duration: SHIFT_DUR, ease: EASE_DECEL, at: p3, fill: 'forwards' as unknown as undefined },
    ],

    // Form slides in
    [
      '.form-container',
      { opacity: [0, 1], transform: ['translateY(100%)', 'translateY(0)'] },
      { duration: FORM_DUR, ease: EASE_DECEL, at: p3 },
    ],
  ];
}

/** Settle delay after the boot animation completes (seconds) */
export const BOOT_SETTLE_DELAY_S = FINAL_SETTLE_S;
