import { webview } from '@kit.ArkWeb';
import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';

const QF_SCROLLING_RELEASE_DELAY_MS: number = 720;

interface WebScrollSmoothModeTabState {
  installed: boolean;
  scrollingActive: boolean;
}

export class WebScrollSmoothModeService {
  private releaseTimersByTabId: Map<string, number> = new Map();
  private stateByTabId: Map<string, WebScrollSmoothModeTabState> = new Map();

  handlePageReadyFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    tabId: string,
    settings: BrowserExperimentSettings
  ): void {
    this.handlePageReady(tabId, runtimeLifecyclePort.resolveController(tabId), settings);
  }

  handlePageReady(
    tabId: string,
    controller: webview.WebviewController | undefined,
    settings: BrowserExperimentSettings
  ): void {
    this.clearReleaseTimer(tabId);
    this.stateByTabId.delete(tabId);
    if (!this.shouldInstallRuntime(settings)) {
      return;
    }
    this.runScript(controller, this.buildInstallScript(settings));
    this.stateByTabId.set(tabId, {
      installed: true,
      scrollingActive: false
    });
  }

  handleScrollMoveFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    tabId: string,
    settings: BrowserExperimentSettings
  ): void {
    this.handleScrollMove(tabId, runtimeLifecyclePort.resolveController(tabId), settings);
  }

  handleScrollMove(
    tabId: string,
    controller: webview.WebviewController | undefined,
    settings: BrowserExperimentSettings
  ): void {
    if (!this.shouldInstallRuntime(settings)) {
      this.clearScrollingState(tabId, controller);
      return;
    }
    const currentState = this.ensureTabState(tabId, controller, settings);
    if (!currentState.scrollingActive) {
      this.runScript(controller, this.buildEnterScrollingScript());
      currentState.scrollingActive = true;
      this.stateByTabId.set(tabId, currentState);
    }
    this.scheduleExit(tabId, controller);
  }

  clearScrollingState(tabId: string, controller: webview.WebviewController | undefined): void {
    this.clearReleaseTimer(tabId);
    const state = this.stateByTabId.get(tabId);
    if (state?.scrollingActive === true) {
      this.runScript(controller, this.buildExitScrollingScript());
    }
    this.stateByTabId.delete(tabId);
  }

  private shouldInstallRuntime(settings: BrowserExperimentSettings): boolean {
    return settings.pauseWebAnimationsDuringScroll || settings.reduceMediaMotionDuringScroll;
  }

  private ensureTabState(
    tabId: string,
    controller: webview.WebviewController | undefined,
    settings: BrowserExperimentSettings
  ): WebScrollSmoothModeTabState {
    const existingState = this.stateByTabId.get(tabId);
    if (existingState !== undefined) {
      return existingState;
    }
    this.runScript(controller, this.buildInstallScript(settings));
    const state: WebScrollSmoothModeTabState = {
      installed: true,
      scrollingActive: false
    };
    this.stateByTabId.set(tabId, state);
    return state;
  }

  private scheduleExit(tabId: string, controller: webview.WebviewController | undefined): void {
    this.clearReleaseTimer(tabId);
    this.releaseTimersByTabId.set(tabId, setTimeout(() => {
      this.releaseTimersByTabId.delete(tabId);
      const state = this.stateByTabId.get(tabId);
      if (state === undefined || !state.scrollingActive) {
        return;
      }
      this.runScript(controller, this.buildExitScrollingScript());
      state.scrollingActive = false;
      this.stateByTabId.set(tabId, state);
    }, QF_SCROLLING_RELEASE_DELAY_MS));
  }

  private clearReleaseTimer(tabId: string): void {
    const timer = this.releaseTimersByTabId.get(tabId) ?? -1;
    if (timer >= 0) {
      clearTimeout(timer);
    }
    this.releaseTimersByTabId.delete(tabId);
  }

  private runScript(controller: webview.WebviewController | undefined, script: string): void {
    if (controller === undefined) {
      return;
    }
    try {
      void controller.runJavaScript(script);
    } catch (_error) {
    }
  }

  private buildInstallScript(settings: BrowserExperimentSettings): string {
    const pauseAnimationsEnabled = settings.pauseWebAnimationsDuringScroll;
    const reduceMediaMotionEnabled = settings.reduceMediaMotionDuringScroll;
    return `(() => {
      try {
        if (window.__qfSmoothModeRuntime && window.__qfSmoothModeRuntime.installed === true) {
          return true;
        }
        var runtime = window.__qfSmoothModeRuntime || {};
        runtime.installed = true;
        runtime.pauseAnimationsEnabled = ${pauseAnimationsEnabled ? 'true' : 'false'};
        runtime.reduceMediaMotionEnabled = ${reduceMediaMotionEnabled ? 'true' : 'false'};
        runtime.markAdIframe = function(frame) {
          try {
            var hint = [
              frame.id || '',
              frame.name || '',
              frame.className || '',
              frame.title || '',
              frame.getAttribute('aria-label') || '',
              frame.src || ''
            ].join(' ').toLowerCase();
            if (/\\b(ad|ads|advert|banner|sponsor|promotion|doubleclick|googlesyndication|taboola|outbrain)\\b/.test(hint)) {
              frame.dataset.qfSmoothAd = '1';
            }
          } catch (error) {}
        };
        runtime.refreshAdIframes = function(root) {
          try {
            var scope = root || document;
            if (scope instanceof HTMLIFrameElement) {
              runtime.markAdIframe(scope);
              return;
            }
            Array.prototype.forEach.call(scope.querySelectorAll('iframe'), function(frame) {
              runtime.markAdIframe(frame);
            });
          } catch (error) {}
        };
        runtime.pauseVideoIfNeeded = function(video) {
          try {
            if (!runtime.reduceMediaMotionEnabled || !(video instanceof HTMLVideoElement)) {
              return;
            }
            if (video.dataset.qfSmoothPaused === '1') {
              return;
            }
            if (video.paused) {
              return;
            }
            video.dataset.qfSmoothPaused = '1';
            video.pause();
          } catch (error) {}
        };
        runtime.observeVideo = function(video) {
          try {
            if (!runtime.reduceMediaMotionEnabled || !(video instanceof HTMLVideoElement)) {
              return;
            }
            if (runtime.videoObserver) {
              runtime.videoObserver.observe(video);
            }
          } catch (error) {}
        };
        runtime.observeExistingVideos = function(root) {
          try {
            if (!runtime.reduceMediaMotionEnabled) {
              return;
            }
            var scope = root || document;
            if (scope instanceof HTMLVideoElement) {
              runtime.observeVideo(scope);
              return;
            }
            Array.prototype.forEach.call(scope.querySelectorAll('video'), function(video) {
              runtime.observeVideo(video);
            });
          } catch (error) {}
        };
        if (!document.getElementById('qf-smooth-mode-style')) {
          var style = document.createElement('style');
          style.id = 'qf-smooth-mode-style';
          style.textContent = [
            'html.qf-scrolling.qf-pause-animations *, html.qf-scrolling.qf-pause-animations *::before, html.qf-scrolling.qf-pause-animations *::after {',
            'animation-play-state: paused !important;',
            'transition-property: none !important;',
            '}',
            'html.qf-scrolling.qf-reduce-media-motion iframe[data-qf-smooth-ad="1"] {',
            'opacity: 0.08 !important;',
            'pointer-events: none !important;',
            '}'
          ].join('');
          (document.head || document.documentElement).appendChild(style);
        }
        if (runtime.pauseAnimationsEnabled) {
          document.documentElement.classList.add('qf-pause-animations');
        } else {
          document.documentElement.classList.remove('qf-pause-animations');
        }
        if (runtime.reduceMediaMotionEnabled) {
          document.documentElement.classList.add('qf-reduce-media-motion');
          if (typeof IntersectionObserver === 'function' && !runtime.videoObserver) {
            runtime.videoObserver = new IntersectionObserver(function(entries) {
              Array.prototype.forEach.call(entries, function(entry) {
                if (entry.isIntersecting) {
                  return;
                }
                runtime.pauseVideoIfNeeded(entry.target);
              });
            }, {
              root: null,
              threshold: 0
            });
          }
          runtime.refreshAdIframes(document);
          runtime.observeExistingVideos(document);
          if (typeof MutationObserver === 'function' && !runtime.mutationObserver && document.documentElement) {
            runtime.mutationObserver = new MutationObserver(function(mutations) {
              Array.prototype.forEach.call(mutations, function(mutation) {
                Array.prototype.forEach.call(mutation.addedNodes || [], function(node) {
                  if (!(node instanceof Element)) {
                    return;
                  }
                  if (node instanceof HTMLIFrameElement) {
                    runtime.markAdIframe(node);
                  } else {
                    runtime.refreshAdIframes(node);
                  }
                  if (node instanceof HTMLVideoElement) {
                    runtime.observeVideo(node);
                  } else {
                    runtime.observeExistingVideos(node);
                  }
                });
              });
            });
            runtime.mutationObserver.observe(document.documentElement, {
              childList: true,
              subtree: true
            });
          }
        } else {
          document.documentElement.classList.remove('qf-reduce-media-motion');
        }
        window.__qfSmoothModeRuntime = runtime;
        return true;
      } catch (error) {
        return false;
      }
    })();`;
  }

  private buildEnterScrollingScript(): string {
    return `(() => {
      try {
        var runtime = window.__qfSmoothModeRuntime;
        if (!runtime || runtime.installed !== true) {
          return false;
        }
        document.documentElement.classList.add('qf-scrolling');
        return true;
      } catch (error) {
        return false;
      }
    })();`;
  }

  private buildExitScrollingScript(): string {
    return `(() => {
      try {
        document.documentElement.classList.remove('qf-scrolling');
        return true;
      } catch (error) {
        return false;
      }
    })();`;
  }
}
