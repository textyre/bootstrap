export function initBackground(): void {
  const bgEl = document.getElementById('background');
  if (!bgEl) return;

  const config = window.greeter_config;
  const utils = window.theme_utils;

  if (!config || !utils) {
    // Dev mode: no greeter API — use noise pattern as fallback
    bgEl.style.background = `
      radial-gradient(ellipse at center, rgba(30,30,30,1) 0%, rgba(0,0,0,1) 100%)
    `;
    return;
  }

  const bgDir = config.branding.background_images_dir;
  if (!bgDir) return;

  utils.dirlist(bgDir, true, (images: string[]) => {
    if (images.length > 0) {
      bgEl.style.backgroundImage = `url('${images[0]}')`;
    }
  });
}
