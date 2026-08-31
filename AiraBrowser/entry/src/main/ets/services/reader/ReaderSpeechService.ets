import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ReaderSpeechVoiceOption,
  ReaderSpeechVoiceSelection,
  buildReaderSpeechVoiceId,
  createDefaultReaderSpeechVoiceOption
} from '../../features/reader/ReaderSpeechModels';

const READER_SPEECH_DOMAIN: number = 0x0000;
const READER_SPEECH_TAG: string = 'ReaderSpeech';

export interface ReaderSpeechProgress {
  currentChunkIndex: number;
  totalChunks: number;
}

export interface ReaderSpeechSpeakOptions {
  startChunkIndex?: number;
  speed?: number;
  voice?: ReaderSpeechVoiceSelection;
}

export interface ReaderSpeechServiceListener {
  onStart?: (progress: ReaderSpeechProgress) => void;
  onChunkStart?: (progress: ReaderSpeechProgress) => void;
  onComplete?: () => void;
  onStop?: () => void;
  onError?: (message: string) => void;
}

export class ReaderSpeechService {
  private engine?: textToSpeech.TextToSpeechEngine;
  private enginePromise?: Promise<textToSpeech.TextToSpeechEngine>;
  private listener?: ReaderSpeechServiceListener;
  private chunks: string[] = [];
  private currentChunkIndex: number = 0;
  private speaking: boolean = false;
  private stopping: boolean = false;
  private activeRequestId: string = '';
  private currentSpeed: number = 1;
  private currentVoice: ReaderSpeechVoiceSelection = createDefaultReaderSpeechVoiceOption();
  private operationGeneration: number = 0;

  setListener(listener: ReaderSpeechServiceListener): void {
    this.listener = listener;
  }

  async speak(chunks: string[], options: ReaderSpeechSpeakOptions = {}): Promise<void> {
    const speakableChunks = chunks.map((chunk: string) => chunk.trim())
      .filter((chunk: string) => chunk.length > 0);
    if (speakableChunks.length <= 0) {
      this.listener?.onError?.('没有可朗读的正文。');
      return;
    }
    const operationGeneration = this.operationGeneration + 1;
    this.operationGeneration = operationGeneration;
    const startChunkIndex = this.clampChunkIndex(options.startChunkIndex ?? 0, speakableChunks.length);
    this.currentSpeed = this.clampSpeechSpeed(options.speed ?? 1);
    this.currentVoice = this.normalizeVoiceSelection(options.voice);
    this.stopCurrentPlayback();
    this.releaseEngine();
    this.chunks = speakableChunks;
    this.currentChunkIndex = startChunkIndex;
    let engine: textToSpeech.TextToSpeechEngine;
    try {
      engine = await this.ensureEngine();
    } catch (error) {
      if (this.operationGeneration !== operationGeneration) {
        return;
      }
      const speechError = error as Error;
      this.listener?.onError?.(speechError.message);
      throw new Error(speechError.message);
    }
    if (this.operationGeneration !== operationGeneration) {
      this.shutdownDetachedEngine(engine);
      return;
    }
    this.stopping = false;
    this.speaking = true;
    this.bindEngineListener(engine);
    this.listener?.onStart?.(this.buildProgress());
    this.speakCurrentChunk(engine);
  }

  async listVoiceOptions(): Promise<ReaderSpeechVoiceOption[]> {
    const fallbackVoice = createDefaultReaderSpeechVoiceOption();
    const queryParams: textToSpeech.VoiceQuery = {
      requestId: `aira_reader_voice_${Date.now()}`,
      online: 1
    };
    try {
      const voices = await textToSpeech.listVoices(queryParams);
      const options = this.normalizeVoiceOptions(voices);
      return options.length > 0 ? options : [fallbackVoice];
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        READER_SPEECH_DOMAIN,
        READER_SPEECH_TAG,
        'list voices failed %{public}s',
        businessError.message ?? JSON.stringify(error)
      );
      return [fallbackVoice];
    }
  }

  async stop(): Promise<void> {
    this.operationGeneration += 1;
    this.stopCurrentPlayback();
  }

  shutdown(): void {
    this.operationGeneration += 1;
    this.stopping = true;
    this.speaking = false;
    this.resetQueue();
    this.releaseEngine();
  }

  resetAfterLifecycleResume(): void {
    this.operationGeneration += 1;
    this.stopping = true;
    this.speaking = false;
    this.resetQueue();
    this.releaseEngine();
  }

  private stopCurrentPlayback(): void {
    this.stopping = true;
    this.speaking = false;
    this.activeRequestId = '';
    const engine = this.engine;
    if (engine === undefined) {
      this.resetQueue();
      this.listener?.onStop?.();
      return;
    }
    try {
      engine.stop();
      this.resetQueue();
      this.listener?.onStop?.();
    } catch (error) {
      hilog.warn(READER_SPEECH_DOMAIN, READER_SPEECH_TAG, 'stop failed %{public}s', JSON.stringify(error));
      this.resetQueue();
      this.listener?.onStop?.();
    }
  }

  private releaseEngine(): void {
    const engine = this.engine;
    this.engine = undefined;
    this.enginePromise = undefined;
    if (engine === undefined) {
      return;
    }
    try {
      engine.shutdown();
    } catch (error) {
      hilog.warn(READER_SPEECH_DOMAIN, READER_SPEECH_TAG, 'shutdown failed %{public}s', JSON.stringify(error));
    }
  }

  private async ensureEngine(): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.engine !== undefined) {
      return this.engine;
    }
    if (this.enginePromise !== undefined) {
      return this.enginePromise;
    }
    const initParams: textToSpeech.CreateEngineParams = {
      language: this.currentVoice.language,
      person: this.currentVoice.person,
      online: 1,
      extraParams: {
        'style': this.currentVoice.style,
        'locate': 'CN',
        'name': 'AiraReaderSpeech',
        'isBackStage': true
      }
    };
    const enginePromise = textToSpeech.createEngine(initParams);
    this.enginePromise = enginePromise;
    try {
      const engine = await enginePromise;
      if (this.enginePromise === enginePromise) {
        this.engine = engine;
      }
      return engine;
    } catch (error) {
      const businessError = error as BusinessError;
      const message = businessError.message ?? '系统朗读引擎初始化失败。';
      if (this.enginePromise === enginePromise) {
        this.enginePromise = undefined;
      }
      throw new Error(message);
    }
  }

  private shutdownDetachedEngine(engine: textToSpeech.TextToSpeechEngine): void {
    if (this.engine === engine) {
      this.engine = undefined;
      this.enginePromise = undefined;
    }
    try {
      engine.shutdown();
    } catch (error) {
      hilog.warn(READER_SPEECH_DOMAIN, READER_SPEECH_TAG, 'stale engine shutdown failed %{public}s', JSON.stringify(error));
    }
  }

  private bindEngineListener(engine: textToSpeech.TextToSpeechEngine): void {
    const speakListener: textToSpeech.SpeakListener = {
      onStart: (requestId: string, _response: textToSpeech.StartResponse): void => {
        if (requestId !== this.activeRequestId) {
          return;
        }
        this.listener?.onChunkStart?.(this.buildProgress());
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
        if (requestId !== this.activeRequestId || this.stopping) {
          return;
        }
        if (response.type !== 1) {
          return;
        }
        this.currentChunkIndex += 1;
        if (this.currentChunkIndex >= this.chunks.length) {
          this.speaking = false;
          this.resetQueue();
          this.listener?.onComplete?.();
          return;
        }
        this.speakCurrentChunk(engine);
      },
      onStop: (requestId: string, _response: textToSpeech.StopResponse): void => {
        if (requestId.length > 0 && requestId !== this.activeRequestId) {
          return;
        }
        this.resetQueue();
        this.listener?.onStop?.();
      },
      onError: (requestId: string, errorCode: number, errorMessage: string): void => {
        if (requestId.length > 0 && requestId !== this.activeRequestId) {
          return;
        }
        this.speaking = false;
        this.resetQueue();
        this.listener?.onError?.(this.buildErrorMessage(errorCode, errorMessage));
      },
      onData: (_requestId: string, _audio: ArrayBuffer, _response: textToSpeech.SynthesisResponse): void => {}
    };
    engine.setListener(speakListener);
  }

  private speakCurrentChunk(engine: textToSpeech.TextToSpeechEngine): void {
    if (!this.speaking || this.stopping || this.currentChunkIndex >= this.chunks.length) {
      return;
    }
    const requestId = `aira_reader_${Date.now()}_${this.currentChunkIndex}`;
    this.activeRequestId = requestId;
    const speakParams: textToSpeech.SpeakParams = {
      requestId: requestId,
      extraParams: {
        'queueMode': 0,
        'speed': this.currentSpeed,
        'volume': 2,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'soundChannel': 1,
        'playType': 1
      }
    };
    try {
      engine.speak(this.chunks[this.currentChunkIndex], speakParams);
    } catch (error) {
      const businessError = error as BusinessError;
      this.speaking = false;
      this.resetQueue();
      this.listener?.onError?.(businessError.message ?? '朗读启动失败。');
    }
  }

  private buildProgress(): ReaderSpeechProgress {
    return {
      currentChunkIndex: Math.min(this.currentChunkIndex + 1, this.chunks.length),
      totalChunks: this.chunks.length
    };
  }

  private clampChunkIndex(index: number, totalChunks: number): number {
    if (totalChunks <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(Math.floor(index), totalChunks - 1));
  }

  private clampSpeechSpeed(speed: number): number {
    return Math.max(0.5, Math.min(2, speed));
  }

  private normalizeVoiceSelection(voice?: ReaderSpeechVoiceSelection): ReaderSpeechVoiceSelection {
    const fallbackVoice = createDefaultReaderSpeechVoiceOption();
    if (voice === undefined) {
      return fallbackVoice;
    }
    const language = voice.language.trim().length > 0 ? voice.language.trim() : fallbackVoice.language;
    const style = voice.style.trim().length > 0 ? voice.style.trim() : fallbackVoice.style;
    const person = Number.isFinite(voice.person) ? Math.max(0, Math.floor(voice.person)) : fallbackVoice.person;
    return {
      id: buildReaderSpeechVoiceId(language, person, style),
      language: language,
      person: person,
      style: style
    };
  }

  private normalizeVoiceOptions(voices: textToSpeech.VoiceInfo[]): ReaderSpeechVoiceOption[] {
    const options: ReaderSpeechVoiceOption[] = [];
    const usedIds: Record<string, boolean> = {};
    voices.forEach((voice: textToSpeech.VoiceInfo) => {
      const option = this.normalizeVoiceOption(voice);
      if (option.id.length <= 0 || usedIds[option.id] === true || !this.isChineseVoice(option.language)) {
        return;
      }
      usedIds[option.id] = true;
      options.push(option);
    });
    return options;
  }

  private normalizeVoiceOption(voice: textToSpeech.VoiceInfo): ReaderSpeechVoiceOption {
    const fallbackVoice = createDefaultReaderSpeechVoiceOption();
    const language = voice.language.trim().length > 0 ? voice.language.trim() : fallbackVoice.language;
    const style = voice.style.trim().length > 0 ? voice.style.trim() : fallbackVoice.style;
    const person = Number.isFinite(voice.person) ? Math.max(0, Math.floor(voice.person)) : fallbackVoice.person;
    const status = voice.status ?? '';
    const title = voice.description.trim().length > 0 ?
      voice.description.trim() : this.buildVoiceTitle(language, person, voice.gender);
    return {
      id: buildReaderSpeechVoiceId(language, person, style),
      title: title,
      helperText: this.buildVoiceHelperText(language, style, voice.gender, status),
      language: language,
      person: person,
      style: style,
      gender: voice.gender,
      status: status,
      isAvailable: this.isVoiceAvailable(status)
    };
  }

  private buildVoiceTitle(language: string, person: number, gender: string): string {
    const genderLabel = this.resolveGenderLabel(gender);
    if (genderLabel.length > 0) {
      return `${this.resolveLanguageLabel(language)}${genderLabel}`;
    }
    return `${this.resolveLanguageLabel(language)}音色 ${person}`;
  }

  private buildVoiceHelperText(language: string, style: string, gender: string, status: string): string {
    const parts: string[] = [this.resolveLanguageLabel(language)];
    const genderLabel = this.resolveGenderLabel(gender);
    if (genderLabel.length > 0) {
      parts.push(genderLabel);
    }
    if (style.trim().length > 0) {
      parts.push(style.trim());
    }
    if (status.trim().length > 0) {
      parts.push(status.trim());
    }
    return parts.join(' · ');
  }

  private resolveLanguageLabel(language: string): string {
    const normalized = language.trim().toLowerCase();
    if (normalized === 'zh-cn' || normalized === 'zh_cn') {
      return '中文';
    }
    if (normalized === 'en-us' || normalized === 'en_us') {
      return '英语';
    }
    return language.trim().length > 0 ? language.trim() : '系统';
  }

  private resolveGenderLabel(gender: string): string {
    const normalized = gender.trim().toLowerCase();
    if (normalized === 'female' || normalized === 'woman') {
      return '女声';
    }
    if (normalized === 'male' || normalized === 'man') {
      return '男声';
    }
    return gender.trim();
  }

  private isVoiceAvailable(status: string): boolean {
    return status.trim().toLowerCase() !== 'unavailable';
  }

  private isChineseVoice(language: string): boolean {
    const normalized = language.trim().toLowerCase();
    return normalized === 'zh' || normalized === 'zh-cn' || normalized === 'zh_cn';
  }

  private buildErrorMessage(errorCode: number, errorMessage: string): string {
    if (errorCode === 1002300006) {
      return '系统朗读服务正忙，请稍后再试。';
    }
    if (errorCode === 1002300007) {
      return '系统朗读引擎还没有准备好。';
    }
    if (errorCode === 1002300001) {
      return '正文内容暂时不能朗读。';
    }
    return errorMessage.length > 0 ? errorMessage : '朗读失败，请稍后再试。';
  }

  private resetQueue(): void {
    this.chunks = [];
    this.currentChunkIndex = 0;
    this.activeRequestId = '';
    this.stopping = false;
  }
}
