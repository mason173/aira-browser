export type ReaderSpeechPlaybackStatus = 'idle' | 'preparing' | 'speaking' | 'paused' | 'stopping' | 'error';

export interface ReaderSpeechState {
  status: ReaderSpeechPlaybackStatus;
  currentChunkIndex: number;
  totalChunks: number;
  message: string;
}

export interface ReaderSpeechVoiceSelection {
  id: string;
  language: string;
  person: number;
  style: string;
}

export interface ReaderSpeechVoiceOption extends ReaderSpeechVoiceSelection {
  title: string;
  helperText: string;
  gender: string;
  status: string;
  isAvailable: boolean;
}

export function createDefaultReaderSpeechState(): ReaderSpeechState {
  return {
    status: 'idle',
    currentChunkIndex: 0,
    totalChunks: 0,
    message: ''
  };
}

export function isReaderSpeechActive(state: ReaderSpeechState): boolean {
  return state.status === 'preparing' || state.status === 'speaking' || state.status === 'stopping';
}

export function isReaderSpeechPaused(state: ReaderSpeechState): boolean {
  return state.status === 'paused';
}

export function shouldResetReaderSpeechStateOnStop(state: ReaderSpeechState): boolean {
  return state.status !== 'stopping' && state.status !== 'paused' && state.status !== 'preparing';
}

export function createDefaultReaderSpeechVoiceOption(): ReaderSpeechVoiceOption {
  return {
    id: buildReaderSpeechVoiceId('zh-CN', 0, 'interaction-broadcast'),
    title: '系统默认音色',
    helperText: '中文在线朗读',
    language: 'zh-CN',
    person: 0,
    style: 'interaction-broadcast',
    gender: '',
    status: '',
    isAvailable: true
  };
}

export function buildReaderSpeechVoiceId(language: string, person: number, style: string): string {
  return `${language.trim()}#${Math.floor(person)}#${style.trim()}`;
}
