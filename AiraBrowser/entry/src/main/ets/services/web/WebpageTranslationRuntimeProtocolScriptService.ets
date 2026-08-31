export const TRANSLATION_RUNTIME_NAME: string = '__aira_translation__';
export const TRANSLATION_RUNTIME_VERSION: string = 'wrapper_cache_v18_translation_only_default';

export class WebpageTranslationRuntimeProtocolScriptService {
  buildExtractVisibleBatchScript(limitNodes: number, limitChars: number): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.extractVisibleBatch?.(${limitNodes}, ${limitChars}) || ''`;
  }

  buildExtractPageQueueScript(limitNodes: number, limitChars: number, maxItemChars: number): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.extractPageQueue?.(${limitNodes}, ${limitChars}, ${maxItemChars}) || ''`;
  }

  buildExtractPendingBatchScript(limitNodes: number, limitChars: number): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.extractPendingBatch?.(${limitNodes}, ${limitChars}) || ''`;
  }

  buildApplyTranslationsScript(payloadJson: string): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.applyTranslations?.(${JSON.stringify(payloadJson)}) || 'not_installed'`;
  }

  buildMarkLoadingScript(payloadJson: string): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.markLoading?.(${JSON.stringify(payloadJson)}) || 'not_installed'`;
  }

  buildClearLoadingScript(payloadJson: string): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.clearLoading?.(${JSON.stringify(payloadJson)}) || 'not_installed'`;
  }

  buildMarkFailedScript(payloadJson: string): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.markFailed?.(${JSON.stringify(payloadJson)}) || 'not_installed'`;
  }

  buildClearTransientStatesScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.clearTransientStates?.() || 'not_installed'`;
  }

  buildConfigureCacheScript(namespace: string): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.configureCache?.(${JSON.stringify(namespace)}) || 'not_installed'`;
  }

  buildRestoreOriginalsScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.restoreOriginals?.() || 'not_installed'`;
  }

  buildShowBilingualTranslationsScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.showBilingualTranslations?.() || 'not_installed'`;
  }

  buildShowTranslationOnlyScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.showTranslationOnly?.() || 'not_installed'`;
  }

  buildClearScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.clear?.() || 'not_installed'`;
  }

  buildStartObserverScript(debounceMs: number): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.startObserver?.(${debounceMs}) || 'not_installed'`;
  }

  buildStopObserverScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.stopObserver?.() || 'not_installed'`;
  }

  buildInstallSpaHooksScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.installSpaHooks?.() || 'not_installed'`;
  }

  buildGetPageSignalVersionScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.getPageSignalVersion?.() || '0'`;
  }

  buildGetRouteSignalVersionScript(): string {
    return `window.${TRANSLATION_RUNTIME_NAME}?.getRouteSignalVersion?.() || '0'`;
  }
}
