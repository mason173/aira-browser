import { inputConsumer, KeyCode, KeyEvent } from '@kit.InputKit';

export class NovelReaderVolumeKeyOwner {}

export class NovelReaderVolumeKeyService {
  private activeOwner?: NovelReaderVolumeKeyOwner = undefined;
  private volumeUpRegistered: boolean = false;
  private volumeDownRegistered: boolean = false;
  private onPrevious: () => void = () => {};
  private onNext: () => void = () => {};
  private readonly volumeUpKeyPressedCallback = (_event: KeyEvent): void => {
    this.onPrevious();
  };
  private readonly volumeDownKeyPressedCallback = (_event: KeyEvent): void => {
    this.onNext();
  };

  createOwner(): NovelReaderVolumeKeyOwner {
    return new NovelReaderVolumeKeyOwner();
  }

  enable(
    owner: NovelReaderVolumeKeyOwner,
    onPrevious: () => void,
    onNext: () => void
  ): boolean {
    if (this.activeOwner === owner && this.volumeUpRegistered && this.volumeDownRegistered) {
      this.onPrevious = onPrevious;
      this.onNext = onNext;
      return true;
    }
    this.releaseActiveOwner();
    this.activeOwner = owner;
    this.onPrevious = onPrevious;
    this.onNext = onNext;
    try {
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: 1,
        isRepeat: false
      }, this.volumeUpKeyPressedCallback);
      this.volumeUpRegistered = true;
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: 1,
        isRepeat: false
      }, this.volumeDownKeyPressedCallback);
      this.volumeDownRegistered = true;
      return true;
    } catch (_error) {
      this.releaseActiveOwner();
      return false;
    }
  }

  disable(owner: NovelReaderVolumeKeyOwner): void {
    if (this.activeOwner !== owner) {
      return;
    }
    this.releaseActiveOwner();
  }

  private releaseActiveOwner(): void {
    if (this.volumeUpRegistered) {
      try {
        inputConsumer.off('keyPressed', this.volumeUpKeyPressedCallback);
      } catch (_error) {
      }
    }
    if (this.volumeDownRegistered) {
      try {
        inputConsumer.off('keyPressed', this.volumeDownKeyPressedCallback);
      } catch (_error) {
      }
    }
    this.volumeUpRegistered = false;
    this.volumeDownRegistered = false;
    this.activeOwner = undefined;
    this.onPrevious = () => {};
    this.onNext = () => {};
  }
}

export const sharedNovelReaderVolumeKeyService: NovelReaderVolumeKeyService =
  new NovelReaderVolumeKeyService();
