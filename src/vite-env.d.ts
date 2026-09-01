/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_AIRATAB_DISTRIBUTION?: 'community' | 'official';
  readonly VITE_AIRATAB_OFFICIAL_API_ROUTES?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare module '*.png?url' {
  const content: string;
  export default content;
}
