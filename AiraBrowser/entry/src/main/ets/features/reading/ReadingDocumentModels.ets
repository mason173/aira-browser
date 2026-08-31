export type ReadingBlockType =
  'heading' |
  'paragraph' |
  'image' |
  'link' |
  'quote' |
  'list_item' |
  'code';

export interface ReadingDocumentBlock {
  id: string;
  type: ReadingBlockType;
  text: string;
  url?: string;
  originalUrl?: string;
  fallbackUrls?: string[];
  alt?: string;
  caption?: string;
  level?: number;
  width?: number;
  height?: number;
  renderedWidth?: number;
  renderedHeight?: number;
  qualityScore?: number;
  hiddenReason?: string;
  imageFailurePolicy?: string;
}

export interface ReadingDocument {
  id: string;
  title: string;
  subtitle: string;
  blocks: ReadingDocumentBlock[];
}

export interface ReadingAnchor {
  documentId: string;
  blockId: string;
  characterOffset: number;
  blockFingerprint?: string;
  blockIndex?: number;
  contextBefore?: string;
  contextAfter?: string;
}

export function createReadingAnchor(
  documentId: string,
  blockId: string,
  characterOffset: number,
  blockFingerprint: string = '',
  blockIndex: number = -1,
  contextBefore: string = '',
  contextAfter: string = ''
): ReadingAnchor {
  return {
    documentId: documentId,
    blockId: blockId,
    characterOffset: Math.max(0, Math.floor(characterOffset)),
    blockFingerprint: blockFingerprint,
    blockIndex: Math.floor(blockIndex),
    contextBefore: contextBefore,
    contextAfter: contextAfter
  };
}

export function buildReadingTextFingerprint(value: string): string {
  let hash: number = 2166136261;
  for (let index: number = 0; index < value.length; index++) {
    hash = hash ^ value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `${value.length.toString(36)}-${(hash >>> 0).toString(16)}`;
}

export function buildReadingBlockFingerprint(block: ReadingDocumentBlock): string {
  return buildReadingTextFingerprint([
    block.type,
    block.text,
    block.url ?? '',
    block.originalUrl ?? '',
    block.alt ?? '',
    block.caption ?? '',
    `${block.level ?? 0}`,
    `${block.width ?? 0}`,
    `${block.height ?? 0}`,
    `${block.renderedWidth ?? 0}`,
    `${block.renderedHeight ?? 0}`,
    block.hiddenReason ?? '',
    block.imageFailurePolicy ?? ''
  ].join('\u001f'));
}
