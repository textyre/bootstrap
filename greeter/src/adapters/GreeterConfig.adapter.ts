export interface IGreeterConfigAdapter {
  getBackgroundImagesDir(): string | null;
  listImages(dir: string, callback: (images: string[]) => void): void;
}

export class GreeterConfigAdapter implements IGreeterConfigAdapter {
  private readonly config: any;
  private readonly utils: any;

  constructor() {
    this.config = window.greeter_config;
    this.utils = window.theme_utils;
  }

  getBackgroundImagesDir(): string | null {
    return this.config?.branding?.background_images_dir ?? null;
  }

  listImages(dir: string, callback: (images: string[]) => void): void {
    this.utils?.dirlist(dir, true, callback);
  }
}
