import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface BrowserVolumeKeyAudioHost {
  isWebPageForeground: () => boolean;
  unmuteActiveAutomaticallyMutedTab: () => void;
}

/** System volume-bar changes express a user request to hear the foreground page. */
export class BrowserVolumeKeyAudioService {
  private readonly host: BrowserVolumeKeyAudioHost;
  private volumeManager?: audio.AudioVolumeManager;
  private listening: boolean = false;
  // AudioKit rejects one callback registered against different stream usages.
  private readonly musicVolumeChanged: (event: audio.StreamVolumeEvent) => void = (event: audio.StreamVolumeEvent): void => {
    this.handleVolumeChanged(event);
  };
  private readonly movieVolumeChanged: (event: audio.StreamVolumeEvent) => void = (event: audio.StreamVolumeEvent): void => {
    this.handleVolumeChanged(event);
  };

  private handleVolumeChanged(event: audio.StreamVolumeEvent): void {
    if (!this.listening || !event.updateUi || !this.host.isWebPageForeground()) {
      return;
    }
    if (event.streamUsage !== audio.StreamUsage.STREAM_USAGE_MUSIC &&
      event.streamUsage !== audio.StreamUsage.STREAM_USAGE_MOVIE) {
      return;
    }
    this.host.unmuteActiveAutomaticallyMutedTab();
  }

  constructor(host: BrowserVolumeKeyAudioHost) {
    this.host = host;
  }

  start(): void {
    if (this.listening) {
      return;
    }
    try {
      this.volumeManager = audio.getAudioManager().getVolumeManager();
      this.listening = true;
      this.volumeManager.on('streamVolumeChange', audio.StreamUsage.STREAM_USAGE_MUSIC, this.musicVolumeChanged);
      this.volumeManager.on('streamVolumeChange', audio.StreamUsage.STREAM_USAGE_MOVIE, this.movieVolumeChanged);
    } catch (error) {
      this.stop();
      hilog.warn(0x0000, 'BrowserVolumeKeyAudio', 'Volume listener registration failed: %{public}s', `${error}`);
    }
  }

  stop(): void {
    this.listening = false;
    const manager = this.volumeManager;
    this.volumeManager = undefined;
    if (manager === undefined) {
      return;
    }
    this.removeListener(manager, this.musicVolumeChanged);
    this.removeListener(manager, this.movieVolumeChanged);
  }

  private removeListener(
    manager: audio.AudioVolumeManager,
    callback: (event: audio.StreamVolumeEvent) => void
  ): void {
    try {
      manager.off('streamVolumeChange', callback);
    } catch (error) {
      hilog.warn(0x0000, 'BrowserVolumeKeyAudio', 'Volume listener cleanup failed: %{public}s', `${error}`);
    }
  }
}
