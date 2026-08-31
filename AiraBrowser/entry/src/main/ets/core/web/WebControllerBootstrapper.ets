import { webview } from '@kit.ArkWeb';

export interface WebControllerBootstrapConfig {
  downloadDelegate?: webview.WebDownloadDelegate;
}

export class WebControllerBootstrapper {
  bootstrapAttachedController(
    controller: webview.WebviewController,
    config: WebControllerBootstrapConfig
  ): void {
    try {
      controller.enableAdsBlock(false);
    } catch (_error) {
    }

    if (config.downloadDelegate !== undefined) {
      try {
        controller.setDownloadDelegate(config.downloadDelegate);
      } catch (_error) {
      }
    }

    try {
      controller.setErrorPageEnabled(true);
    } catch (_error) {
    }

  }
}
