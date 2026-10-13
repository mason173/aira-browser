import { BookmarkStorageScope } from './BrowserModels';

export interface BookmarkSearchRecord {
  id: string;
  title: string;
  url: string;
}

export interface BookmarkSearchIndexSource {
  revision: string;
  records: BookmarkSearchRecord[];
}

export interface BookmarkSearchIndexSnapshot {
  revision: string;
  chunks: string[];
}

/** Lazy, authoritative search storage; independent of bookmark-manager initialization. */
export interface BookmarkSearchIndexStore {
  readRevision(): Promise<string>;
  load(scope: BookmarkStorageScope): Promise<BookmarkSearchIndexSnapshot | undefined>;
  readSource(scope: BookmarkStorageScope): Promise<BookmarkSearchIndexSource | undefined>;
  save(scope: BookmarkStorageScope, revision: string, chunks: string[]): Promise<boolean>;
}
