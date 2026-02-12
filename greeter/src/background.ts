export function initBackground(): void {
  const bgEl = document.getElementById('background');
  if (!bgEl) return;

  const config = window.greeter_config;
  const utils = window.theme_utils;

  if (!config || !utils) return;

  try {
    const bgDir = config.branding.background_images_dir;
    if (!bgDir) return;

    utils.dirlist(bgDir, true, (images: string[]) => {
      if (images.length > 0) {
        bgEl.style.backgroundImage = `url('${images[0]}')`;
      }
    });
  } catch {
    // greeter API not available — CSS background is fine
  }
}
