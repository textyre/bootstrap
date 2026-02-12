/**
 * Boot animation orchestrator for the ctOS greeter.
 *
 * Controls the power-on sequence by toggling CSS animation classes
 * on HUD elements in a timed sequence. All visual motion is defined
 * in _boot.css; this module handles sequencing only.
 */

function awaitAnimation(el: Element): Promise<void> {
  return new Promise((resolve) => {
    el.addEventListener('animationend', () => resolve(), { once: true });
  });
}

function wait(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function trigger(el: Element, triggerClass: string): void {
  el.classList.remove('boot-pre');
  el.classList.add(triggerClass);
}

/**
 * Run the full boot animation sequence.
 * Resolves when all animations are complete and the UI is ready for interaction.
 */
export async function runBootAnimation(): Promise<void> {
  // Reduced motion — show everything immediately
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.querySelectorAll('.boot-pre').forEach((el) => {
      el.classList.remove('boot-pre');
    });
    return;
  }

  const ctosBlock = document.getElementById('ctos-block');
  const osText = document.querySelector('.os') as HTMLElement | null;
  const ctosLogo = document.getElementById('ctos-logo');
  const formContainer = document.querySelector('.form-container') as HTMLElement | null;
  const license = document.getElementById('license');
  const rightEdge = document.getElementById('right-edge');
  const securityMeta = document.getElementById('security-meta');
  const clock = document.getElementById('clock');
  const dateBox = document.getElementById('date-box');
  const archLogo = document.getElementById('arch-logo');
  const envBlock = document.getElementById('env-block');
  // === PHASE 1: Logo loader (300ms delay) ===
  await wait(300);

  if (ctosBlock) trigger(ctosBlock, 'boot-loading');
  if (license) trigger(license, 'boot-enter');

  // At ~50% of loader (600ms in), trigger all peripheral elements
  const peripheralsDone = wait(600).then(() => {
    if (rightEdge) trigger(rightEdge, 'boot-flicker');
    if (securityMeta) trigger(securityMeta, 'boot-slide');

    if (archLogo) trigger(archLogo, 'boot-enter');
    if (clock) trigger(clock, 'boot-enter');
    if (dateBox) trigger(dateBox, 'boot-enter');

    if (envBlock) trigger(envBlock, 'boot-expand');
  });

  // Wait for loader to finish (0 → 250px)
  if (ctosBlock) await awaitAnimation(ctosBlock);

  // === PHASE 2: Block pulls back (250 → 170px) + OS text reveals ===
  await wait(300);

  if (ctosBlock) {
    ctosBlock.classList.add('boot-pullback');
    ctosBlock.classList.remove('boot-loading');
  }

  if (osText) {
    trigger(osText, 'boot-reveal');
  }

  // Wait for pullback to finish
  if (ctosBlock) await awaitAnimation(ctosBlock);

  // === PHASE 3: Logo shifts up, form slides in ===
  if (ctosLogo) trigger(ctosLogo, 'boot-shift-up');

  if (formContainer) {
    trigger(formContainer, 'boot-enter');
    await awaitAnimation(formContainer);
  }

  // Ensure peripherals have settled
  await peripheralsDone;

  await wait(100);
}
