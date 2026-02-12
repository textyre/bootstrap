export interface IGreeterConfigAdapter {
  getBackgroundImagesDir(): string | null;
  listImages(dir: string, callback: (images: string[]) => void): void;
}

export function createGreeterConfigAdapter(): IGreeterConfigAdapter {
  const config = window.greeter_config;
  const utils = window.theme_utils;

  return {
    getBackgroundImagesDir() {
      return config?.branding?.background_images_dir ?? null;
    },
    listImages(dir, callback) {
      utils?.dirlist(dir, true, callback);
    },
  };
}
