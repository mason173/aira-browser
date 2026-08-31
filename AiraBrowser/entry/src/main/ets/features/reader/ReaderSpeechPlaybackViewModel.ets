import {
  ReaderSpeechPlaybackStatus,
  ReaderSpeechState,
  ReaderSpeechVoiceOption,
  createDefaultReaderSpeechState,
  isReaderSpeechActive,
  isReaderSpeechPaused
} from './ReaderSpeechModels';

export class ReaderSpeechPlaybackViewModel {
  buildStoppingState(state: ReaderSpeechState): ReaderSpeechState {
    return {
      status: 'stopping',
      currentChunkIndex: state.currentChunkIndex,
      totalChunks: state.totalChunks,
      message: ''
    };
  }

  buildPausedState(state: ReaderSpeechState, totalChunks: number): ReaderSpeechState {
    const safeTotalChunks = this.resolveSafeTotalChunks(state, totalChunks);
    return {
      status: 'paused',
      currentChunkIndex: this.resolveSafeOneBasedChunkIndex(state.currentChunkIndex, safeTotalChunks),
      totalChunks: safeTotalChunks,
      message: ''
    };
  }

  buildPreparingState(startChunkIndex: number, totalChunks: number): ReaderSpeechState {
    const safeTotalChunks = Math.max(0, Math.floor(totalChunks));
    const safeStartIndex = this.clampChunkIndex(startChunkIndex, safeTotalChunks);
    return {
      status: 'preparing',
      currentChunkIndex: safeStartIndex + 1,
      totalChunks: safeTotalChunks,
      message: ''
    };
  }

  buildProgressState(
    status: ReaderSpeechPlaybackStatus,
    currentChunkIndex: number,
    totalChunks: number,
    message: string
  ): ReaderSpeechState {
    return {
      status: status,
      currentChunkIndex: Math.max(0, Math.floor(currentChunkIndex)),
      totalChunks: Math.max(0, Math.floor(totalChunks)),
      message: message
    };
  }

  buildErrorState(message: string): ReaderSpeechState {
    return {
      status: 'error',
      currentChunkIndex: 0,
      totalChunks: 0,
      message: message
    };
  }

  resolvePlaybackStartChunkIndex(state: ReaderSpeechState, totalChunks: number): number {
    if (isReaderSpeechPaused(state)) {
      return this.resolveCurrentChunkStartIndex(state, totalChunks);
    }
    return 0;
  }

  resolveCurrentChunkStartIndex(state: ReaderSpeechState, totalChunks: number): number {
    if (totalChunks <= 0) {
      return 0;
    }
    const index = state.currentChunkIndex > 0 ? state.currentChunkIndex - 1 : 0;
    return this.clampChunkIndex(index, totalChunks);
  }

  clampChunkIndex(index: number, totalChunks: number): number {
    if (totalChunks <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(Math.floor(index), Math.floor(totalChunks) - 1));
  }

  clampSpeechSpeed(speed: number): number {
    return Math.max(0.5, Math.min(2, speed));
  }

  shouldAutoStartPlayer(state: ReaderSpeechState): boolean {
    return !isReaderSpeechActive(state);
  }

  shouldRestartForRuntimeChange(state: ReaderSpeechState): boolean {
    return isReaderSpeechActive(state) || isReaderSpeechPaused(state);
  }

  reconcileChunksState(
    currentState: ReaderSpeechState,
    currentChunks: string[],
    nextChunks: string[]
  ): ReaderSpeechState {
    if (this.chunksEqual(currentChunks, nextChunks)) {
      return currentState;
    }
    return createDefaultReaderSpeechState();
  }

  chunksEqual(currentChunks: string[], nextChunks: string[]): boolean {
    if (currentChunks.length !== nextChunks.length) {
      return false;
    }
    for (let index = 0; index < currentChunks.length; index += 1) {
      if (currentChunks[index] !== nextChunks[index]) {
        return false;
      }
    }
    return true;
  }

  resolveSelectedVoiceId(voice?: ReaderSpeechVoiceOption): string {
    return voice?.id ?? '';
  }

  resolveVoiceLabel(voice?: ReaderSpeechVoiceOption): string {
    return voice?.title ?? '系统默认音色';
  }

  private resolveSafeTotalChunks(state: ReaderSpeechState, totalChunks: number): number {
    if (state.totalChunks > 0) {
      return state.totalChunks;
    }
    return Math.max(0, Math.floor(totalChunks));
  }

  private resolveSafeOneBasedChunkIndex(currentChunkIndex: number, totalChunks: number): number {
    if (totalChunks <= 0) {
      return 1;
    }
    const fallbackIndex = currentChunkIndex > 0 ? currentChunkIndex : 1;
    return Math.max(1, Math.min(Math.floor(fallbackIndex), totalChunks));
  }
}
