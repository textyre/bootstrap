import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'es2022',
    minify: 'esbuild',
    cssMinify: 'esbuild',
    cssCodeSplit: false,
    sourcemap: false,
    rollupOptions: {
      output: { compact: true },
      treeshake: {
        moduleSideEffects: 'no-external',
        propertyReadSideEffects: false,
        tryCatchDeoptimization: false,
      },
    },
  },
  esbuild: {
    legalComments: 'none',
    treeShaking: true,
  },
});
