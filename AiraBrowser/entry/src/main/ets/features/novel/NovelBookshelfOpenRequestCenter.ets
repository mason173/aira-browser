import {
  cloneNovelBookshelfBook,
  NovelBookshelfBook
} from './NovelLibraryModels';
import { sharedNovelSourceIdentityService } from '../../services/novel/NovelSourceIdentityService';

const NOVEL_BOOKSHELF_OPEN_REQUEST_TTL_MS: number = 15 * 1000;

interface NovelBookshelfOpenRequest {
  detailIdentity: string;
  book: NovelBookshelfBook;
  createdAt: number;
}

let pendingRequest: NovelBookshelfOpenRequest | undefined = undefined;

export function requestNovelBookshelfTakeover(book: NovelBookshelfBook): void {
  const detailIdentity: string = sharedNovelSourceIdentityService.normalizeUrl(book.detailUrl);
  pendingRequest = detailIdentity.length === 0 ? undefined : {
    detailIdentity: detailIdentity,
    book: cloneNovelBookshelfBook(book),
    createdAt: Date.now()
  };
}

export function consumeNovelBookshelfTakeover(detailUrl: string): NovelBookshelfBook | undefined {
  const request: NovelBookshelfOpenRequest | undefined = pendingRequest;
  if (request === undefined) {
    return undefined;
  }
  const expired: boolean = Date.now() - request.createdAt > NOVEL_BOOKSHELF_OPEN_REQUEST_TTL_MS;
  const matches: boolean = !expired && request.detailIdentity ===
    sharedNovelSourceIdentityService.normalizeUrl(detailUrl);
  if (expired || matches) {
    pendingRequest = undefined;
  }
  return matches ? cloneNovelBookshelfBook(request.book) : undefined;
}
