import { MediaResourceDomProbeService } from '../../../services/media/MediaResourceDomProbeService';
import { MediaVideoDomProbeService } from '../../../services/media/MediaVideoDomProbeService';
import { MediaVideoDeepProbeService } from '../../../services/media/MediaVideoDeepProbeService';
import { BrowserMediaDiscoveryCoordinator } from './BrowserMediaDiscoveryCoordinator';
import { BrowserMediaProbeBridge } from './BrowserMediaProbeBridge';
import { BrowserRuntimeLifecyclePort } from '../../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserArkWebMediaTakeoverCoordinator } from './BrowserArkWebMediaTakeoverCoordinator';
import { BrowserMediaFrameRuntimeCoordinator } from './BrowserMediaFrameRuntimeCoordinator';
import { WebVideoPresentationService } from '../../../services/video/WebVideoPresentationService';

export interface BrowserMediaDiscoveryRuntime {
  mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator;
  mediaFrameRuntimeCoordinator: BrowserMediaFrameRuntimeCoordinator;
  arkWebMediaTakeoverCoordinator: BrowserArkWebMediaTakeoverCoordinator;
}

export function createBrowserMediaDiscoveryRuntime(
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort
): BrowserMediaDiscoveryRuntime {
  const mediaProbeBridge = new BrowserMediaProbeBridge(
    new MediaResourceDomProbeService(),
    new MediaVideoDomProbeService(),
    new MediaVideoDeepProbeService()
  );
  const mediaFrameRuntimeCoordinator = new BrowserMediaFrameRuntimeCoordinator();
  const mediaDiscoveryCoordinator =
    new BrowserMediaDiscoveryCoordinator(
      mediaProbeBridge,
      runtimeLifecyclePort
    );
  const arkWebMediaTakeoverCoordinator = new BrowserArkWebMediaTakeoverCoordinator(
    runtimeLifecyclePort,
    new WebVideoPresentationService(mediaFrameRuntimeCoordinator)
  );
  const runtime: BrowserMediaDiscoveryRuntime = {
    mediaDiscoveryCoordinator: mediaDiscoveryCoordinator,
    mediaFrameRuntimeCoordinator: mediaFrameRuntimeCoordinator,
    arkWebMediaTakeoverCoordinator: arkWebMediaTakeoverCoordinator
  };
  return runtime;
}
