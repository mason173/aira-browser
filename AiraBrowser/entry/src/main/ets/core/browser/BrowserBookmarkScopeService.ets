import {
  BookmarkStorageScope,
  BrowserDataScope
} from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserBookmarkScopeRouteParams {
  dataScope?: BrowserDataScope | string;
  privacyMode?: string;
  bookmarkScope?: BookmarkStorageScope | string;
}

export interface BrowserBookmarkRouteParams {
  dataScope: BrowserDataScope | string;
  privacyMode: string;
  boundarySource: string;
  bookmarkScope: BookmarkStorageScope;
}

export class BrowserBookmarkScopeService {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  resolveScopeForBoundary(dataScope: BrowserDataScope | string, privacyMode: string = ''): BookmarkStorageScope {
    return this.profileBoundaryService.resolveBookmarkScope({
      dataScope: dataScope,
      privacyMode: privacyMode
    });
  }

  resolveScopeFromRoute(params: BrowserBookmarkScopeRouteParams | undefined): BookmarkStorageScope {
    const explicitScope = String(params?.bookmarkScope ?? '').trim();
    if (explicitScope === 'private') {
      return 'private';
    }
    if (explicitScope === 'regular') {
      return 'regular';
    }
    return this.resolveScopeForBoundary(params?.dataScope ?? '', params?.privacyMode ?? '');
  }

  buildRouteParams(dataScope: BrowserDataScope | string, privacyMode: string = ''): BrowserBookmarkRouteParams {
    const bookmarkScope = this.resolveScopeForBoundary(dataScope, privacyMode);
    return {
      dataScope: dataScope,
      privacyMode: privacyMode,
      boundarySource: bookmarkScope === 'private' ? 'private_session' : 'profile',
      bookmarkScope: bookmarkScope
    };
  }

  buildTitle(baseTitle: string, scope: BookmarkStorageScope): string {
    return scope === 'private' ? `隐私${baseTitle}` : baseTitle;
  }

  isPrivateScope(scope: BookmarkStorageScope): boolean {
    return scope === 'private';
  }

  shouldRefreshRegularBookmarkSurfaces(scope: BookmarkStorageScope): boolean {
    return scope === 'regular';
  }
}
