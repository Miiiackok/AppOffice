import { defineConfig } from 'vitest/config';

// base 用相对路径：打包后由 Swift 外壳从本地加载
export default defineConfig({
  base: './',
  build: { outDir: 'dist', emptyOutDir: true },
  test: { include: ['src/**/*.test.ts'] },
});
