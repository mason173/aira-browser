import { Want } from '@kit.AbilityKit';
import {
  SharedBrowserUrlIngressResolution,
  SharedBrowserUrlIngressService
} from '../../services/share/SharedBrowserUrlIngressService';

export interface BrowserExternalShareIngressHost {
  openBrowserUrl: (url: string, source: string) => void;
  forwardSharedFile: (want: Want, source: string) => void;
}

export interface BrowserExternalShareIngressRequest {
  handled: boolean;
  completion: Promise<void>;
}

export class BrowserExternalShareIngressCoordinator {
  private readonly service: SharedBrowserUrlIngressService;
  private requestSequence: number = 0;
  private destroyed: boolean = false;

  constructor(service: SharedBrowserUrlIngressService = new SharedBrowserUrlIngressService()) {
    this.service = service;
  }

  handle(want: Want, source: string, host: BrowserExternalShareIngressHost): BrowserExternalShareIngressRequest {
    if (!this.service.isCandidate(want)) {
      return {
        handled: false,
        completion: Promise.resolve()
      };
    }
    const requestId = ++this.requestSequence;
    return {
      handled: true,
      completion: this.resolveAndDispatch(want, source, requestId, host)
    };
  }

  destroy(): void {
    this.destroyed = true;
    this.requestSequence += 1;
  }

  private async resolveAndDispatch(
    want: Want,
    source: string,
    requestId: number,
    host: BrowserExternalShareIngressHost
  ): Promise<void> {
    let resolution: SharedBrowserUrlIngressResolution;
    try {
      resolution = await this.service.resolve(want);
    } catch (_error) {
      resolution = {
        kind: 'unsupported',
        url: ''
      };
    }
    if (this.destroyed || requestId !== this.requestSequence) {
      return;
    }
    if (resolution.kind === 'browser_url') {
      host.openBrowserUrl(resolution.url, source);
      return;
    }
    if (resolution.kind === 'shared_file') {
      host.forwardSharedFile(want, source);
    }
  }
}
