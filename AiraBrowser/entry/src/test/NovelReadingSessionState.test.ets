import { describe, expect, it } from '@ohos/hypium';
import {
  buildNovelChapterRenderKey,
  NovelReadingSessionState,
  NovelSessionCatalogCommit,
  NovelSessionCatalogRequest,
  NovelSessionChapterCommit,
  NovelSessionChapterIntent,
  NovelSessionChapterRequest,
  NovelSessionFailureCode
} from '../main/ets/features/novel/NovelReadingSessionState';

function request(
  requestId: string,
  chapterId: string,
  intent: NovelSessionChapterIntent = 'select',
  startingTrailTailId: string = ''
): NovelSessionChapterRequest {
  return {
    requestId: requestId,
    sessionGeneration: 1,
    tabId: 'tab-1',
    privacyMode: 'regular',
    chapterId: chapterId,
    requestedUrl: `https://example.com/${chapterId}.html`,
    intent: intent,
    startingTrailTailId: startingTrailTailId
  };
}

function commit(chapterId: string, title: string): NovelSessionChapterCommit {
  return {
    chapter: {
      id: chapterId,
      bookId: 'book-1',
      canonicalUrl: `https://example.com/${chapterId}.html`,
      requestedUrl: `https://example.com/${chapterId}.html`,
      finalUrl: `https://example.com/${chapterId}.html`,
      title: title,
      contentKind: 'novel',
      paragraphs: [`${title} opening`, `${title} body`, `${title} ending`],
      images: [],
      prevUrl: '',
      nextUrl: '',
      catalogUrl: 'https://example.com/book-1/',
      revision: 1
    }
  };
}

function catalogRequest(requestId: string): NovelSessionCatalogRequest {
  return {
    requestId: requestId,
    sessionGeneration: 1,
    tabId: 'tab-1',
    privacyMode: 'regular',
    catalogUrl: 'https://example.com/book-1/'
  };
}

function catalogCommit(): NovelSessionCatalogCommit {
  return {
    catalogUrl: 'https://example.com/book-1/',
    chapters: [{
      id: 'chapter-7',
      title: 'Chapter 7',
      canonicalUrl: 'https://example.com/chapter-7.html',
      ordinal: 7
    }],
    complete: true
  };
}

export default function novelReadingSessionStateTest(): void {
  describe('NovelReadingSessionState', () => {
    it('keeps 7 -> 8 -> 7 on the latest explicit Chapter identity', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      const initialChapter7 = request('request-initial-7', 'chapter-7');
      session.beginChapterTransition(initialChapter7);
      session.commitChapter(initialChapter7, commit('chapter-7', 'Chapter 7 initial'));
      const chapter8 = request('request-8', 'chapter-8');
      const chapter7 = request('request-return-7', 'chapter-7');

      session.beginChapterTransition(chapter8);
      session.beginChapterTransition(chapter7);
      const staleCommitted = session.commitChapter(chapter8, commit('chapter-8', 'Chapter 8'));
      const latestCommitted = session.commitChapter(chapter7, commit('chapter-7', 'Chapter 7'));
      const snapshot = session.snapshot();

      expect(staleCommitted).assertFalse();
      expect(latestCommitted).assertTrue();
      expect(snapshot.activeChapterId).assertEqual('chapter-7');
      expect(snapshot.chapterTrail.length).assertEqual(1);
      expect(snapshot.chapterTrail[0].title).assertEqual('Chapter 7');
      expect(snapshot.chapterTransition.status).assertEqual('idle');
    });

    it('keeps catalog and chapter transition status independent', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      const chapter7 = request('chapter-request', 'chapter-7');
      const catalog = catalogRequest('catalog-request');

      session.beginChapterTransition(chapter7);
      session.beginCatalogTransition(catalog);
      const catalogCommitted = session.commitCatalog(catalog, catalogCommit());
      const snapshot = session.snapshot();

      expect(catalogCommitted).assertTrue();
      expect(snapshot.catalogTransition.status).assertEqual('idle');
      expect(snapshot.chapterTransition.status).assertEqual('loading');
      expect(snapshot.catalog.length).assertEqual(1);
    });

    it('replaces for explicit navigation and appends only for vertical continuation', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      const chapter7 = request('request-7', 'chapter-7');
      session.beginChapterTransition(chapter7);
      session.commitChapter(chapter7, commit('chapter-7', 'Chapter 7'));

      const chapter8 = request('request-8', 'chapter-8', 'continue_vertical', 'chapter-7');
      session.beginChapterTransition(chapter8);
      const appended = session.commitChapter(chapter8, commit('chapter-8', 'Chapter 8'));
      expect(appended).assertTrue();
      expect(session.snapshot().chapterTrail.length).assertEqual(2);

      const chapter9 = request('request-9', 'chapter-9', 'next', 'chapter-8');
      session.beginChapterTransition(chapter9);
      const replaced = session.commitChapter(chapter9, commit('chapter-9', 'Chapter 9'));
      const snapshot = session.snapshot();
      expect(replaced).assertTrue();
      expect(snapshot.chapterTrail.length).assertEqual(1);
      expect(snapshot.chapterTrail[0].id).assertEqual('chapter-9');
    });

    it('preserves committed chapter and checkpoint when a transition fails', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      const chapter7 = request('request-7', 'chapter-7');
      session.beginChapterTransition(chapter7);
      session.commitChapter(chapter7, commit('chapter-7', 'Chapter 7'));
      session.recordCheckpoint('chapter-7', 120, 1000);

      const chapter8 = request('request-8', 'chapter-8', 'next', 'chapter-7');
      session.beginChapterTransition(chapter8);
      const failed = session.failChapter(chapter8, 'retryable' as NovelSessionFailureCode);
      const snapshot = session.snapshot();

      expect(failed).assertTrue();
      expect(snapshot.phase).assertEqual('reader');
      expect(snapshot.activeChapterId).assertEqual('chapter-7');
      expect(snapshot.chapterTrail.length).assertEqual(1);
      expect(snapshot.checkpoint.chapterId).assertEqual('chapter-7');
      expect(snapshot.checkpoint.characterOffset).assertEqual(120);
      expect(snapshot.chapterTransition.status).assertEqual('failed');
      expect(snapshot.chapterTransition.failureCode).assertEqual('retryable');
    });

    it('suspends away from the owner tab and resumes without losing content', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      const chapter7 = request('request-7', 'chapter-7');
      session.beginChapterTransition(chapter7);
      session.commitChapter(chapter7, commit('chapter-7', 'Chapter 7'));

      expect(session.suspend('tab-2')).assertTrue();
      expect(session.snapshot().phase).assertEqual('suspended');
      expect(session.snapshot().chapterTrail.length).assertEqual(1);
      expect(session.resume('tab-1')).assertTrue();
      expect(session.snapshot().phase).assertEqual('reader');
      expect(session.snapshot().activeChapterId).assertEqual('chapter-7');
    });

    it('resumes a suspended Book Session as Book', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      expect(session.markBookReady()).assertTrue();

      expect(session.suspend('tab-2')).assertTrue();
      expect(session.resume('tab-1')).assertTrue();
      expect(session.snapshot().phase).assertEqual('book');
    });

    it('rejects an empty canonical Chapter commit', 0, () => {
      const session = new NovelReadingSessionState();
      session.begin('tab-1', 'regular', 'book-1', 1);
      const chapter7 = request('request-7', 'chapter-7');
      const emptyCommit = commit('chapter-7', 'Chapter 7');
      emptyCommit.chapter.paragraphs = ['  '];
      emptyCommit.chapter.images = [];

      session.beginChapterTransition(chapter7);
      expect(session.commitChapter(chapter7, emptyCommit)).assertFalse();
      expect(session.snapshot().chapterTrail.length).assertEqual(0);
    });

    it('keeps private checkpoint memory-only', 0, () => {
      const privateSession = new NovelReadingSessionState();
      privateSession.begin('tab-private', 'private', 'book-1', 1);
      const privateRequest: NovelSessionChapterRequest = {
        requestId: 'private-request',
        sessionGeneration: 1,
        tabId: 'tab-private',
        privacyMode: 'private',
        chapterId: 'chapter-7',
        requestedUrl: 'https://example.com/chapter-7.html',
        intent: 'select',
        startingTrailTailId: ''
      };
      privateSession.beginChapterTransition(privateRequest);
      privateSession.commitChapter(privateRequest, commit('chapter-7', 'Chapter 7'));
      privateSession.recordCheckpoint('chapter-7', 88, 2000);

      expect(privateSession.snapshot().checkpoint.characterOffset).assertEqual(88);
      expect(privateSession.checkpointForPersistence()).assertUndefined();

      const regularSession = new NovelReadingSessionState();
      regularSession.begin('tab-1', 'regular', 'book-1', 1);
      const regularRequest = request('regular-request', 'chapter-7');
      regularSession.beginChapterTransition(regularRequest);
      regularSession.commitChapter(regularRequest, commit('chapter-7', 'Chapter 7'));
      regularSession.recordCheckpoint('chapter-7', 99, 3000);
      expect(regularSession.checkpointForPersistence()?.characterOffset).assertEqual(99);
    });

    it('builds render identity from canonical chapter identity and revision', 0, () => {
      const chapterRevision1 = commit('chapter-7', 'Chapter 7').chapter;
      const chapterRevision2 = commit('chapter-7', 'Chapter 7').chapter;
      chapterRevision2.revision = 2;

      expect(buildNovelChapterRenderKey(chapterRevision1) ===
        buildNovelChapterRenderKey(chapterRevision2)).assertFalse();
    });
  });
}
