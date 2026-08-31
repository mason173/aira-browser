export type BrowserMaterializationPolicy = 'all' | 'active_only' | 'existing_only';

export interface BrowserMaterializationOptions {
  materializationPolicy?: BrowserMaterializationPolicy;
}

export const DEFAULT_BROWSER_MATERIALIZATION_POLICY: BrowserMaterializationPolicy = 'active_only';
