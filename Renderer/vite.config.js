import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: '../App/Resources/Renderer',
    assetsDir: 'assets',
    chunkSizeWarningLimit: 5000,
    cssCodeSplit: false,
    modulePreload: false,
    rolldownOptions: {
      output: {
        entryFileNames: 'assets/[name].js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name][extname]',
        codeSplitting: false,
      },
    },
  },
});
