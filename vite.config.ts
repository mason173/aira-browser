
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import path from 'path';

function getPackageName(id: string): string | null {
  const normalizedId = id.split('\\').join('/');
  const nodeModulesIndex = normalizedId.lastIndexOf('/node_modules/');
  if (nodeModulesIndex === -1) return null;

  const pathAfterNodeModules = normalizedId.slice(nodeModulesIndex + '/node_modules/'.length);
  const cleanPath = pathAfterNodeModules.startsWith('.pnpm/')
    ? pathAfterNodeModules.split('/').slice(1).join('/')
    : pathAfterNodeModules;

  if (!cleanPath) return null;

  const parts = cleanPath.split('/');
  if (parts[0].startsWith('@') && parts.length > 1) {
    return `${parts[0]}/${parts[1]}`;
  }
  return parts[0];
}

function resolveManualChunk(id: string): string | undefined {
  const normalizedId = id.split('\\').join('/');

  if (normalizedId.includes('/src/lazy/')) {
    return 'vendor-lazy';
  }

  const pkg = getPackageName(normalizedId);
  if (!pkg) return undefined;

  if (pkg === 'react' || pkg === 'react-dom' || pkg === 'scheduler') {
    return 'vendor-react';
  }

  if (
    pkg === 'i18next' ||
    pkg === 'react-i18next'
  ) {
    return 'vendor-i18n';
  }

  if (
    pkg === 'next-themes' ||
    pkg === 'use-sync-external-store' ||
    pkg === 'use-sync-external-store/shim'
  ) {
    return 'vendor-theme';
  }

  if (
    pkg === 'clsx' ||
    pkg === 'tailwind-merge' ||
    pkg === 'class-variance-authority'
  ) {
    return 'vendor-style-utils';
  }

  if (
    pkg.startsWith('@radix-ui/') ||
    pkg.startsWith('@floating-ui/')
  ) {
    return 'vendor-ui';
  }

  if (pkg === 'lucide-react') {
    return 'vendor-icons';
  }

  return undefined;
}

export default defineConfig(async () => {
  const { default: tailwindcss } = await import('@tailwindcss/vite');
  const outDir = process.env.VITE_BUILD_OUT_DIR || 'build';
  const appReactPath = path.resolve(__dirname, './node_modules/react');
  const appReactDomPath = path.resolve(__dirname, './node_modules/react-dom');
  return {
  base: './',
  plugins: [react(), tailwindcss()],
    resolve: {
      extensions: ['.js', '.jsx', '.ts', '.tsx', '.json'],
      dedupe: ['react', 'react-dom'],
      alias: {
        react: appReactPath,
        'react/jsx-runtime': path.resolve(appReactPath, 'jsx-runtime.js'),
        'react/jsx-dev-runtime': path.resolve(appReactPath, 'jsx-dev-runtime.js'),
        'react-dom': appReactDomPath,
        'next-themes@0.4.6': 'next-themes',
        'class-variance-authority@0.7.1': 'class-variance-authority',
        '@radix-ui/react-slot@1.1.2': '@radix-ui/react-slot',
        '@radix-ui/react-select@2.1.6': '@radix-ui/react-select',
        '@radix-ui/react-scroll-area@1.2.3': '@radix-ui/react-scroll-area',
        '@radix-ui/react-label@2.1.2': '@radix-ui/react-label',
        '@radix-ui/react-dialog@1.1.6': '@radix-ui/react-dialog',
        '@': path.resolve(__dirname, './src'),
      },
    },
    build: {
      target: 'esnext',
      outDir,
      rollupOptions: {
        input: {
          'background-sw': path.resolve(__dirname, 'src/background.ts'),
          popup: path.resolve(__dirname, 'popup.html'),
        },
        output: {
          entryFileNames: '[name].js',
          manualChunks: resolveManualChunk,
        },
      },
    },
    server: {
      port: 3000,
      open: true,
    },
  };
});
