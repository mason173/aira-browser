import {
  BookmarkCreateNodeCommand,
  BookmarkNode,
  BookmarkReorderChildrenCommand,
  BookmarkStorageScope,
  BookmarkRepositorySnapshot,
  BookmarkMoveSubtreesCommand,
  UpdateBookmarkCommand
} from '../../common/models/BrowserModels';
import {
  AiraBookmarkImportApplyResult,
  AiraBookmarkOverview
} from '../../common/models/AiraSyncModels';
import { BookmarksFeature } from './BookmarksFeature';
import {
  BookmarkMutationService,
  BookmarkUpdateNodeOperation
} from '../../services/bookmarks/BookmarkMutationService';
import { BookmarkHtmlTransferService } from '../../services/bookmarks/BookmarkHtmlTransferService';
import { BookmarkFolderBookmarkCountsResult } from '../../services/bookmarks/BookmarkTreeQueryService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export class BookmarkManagementBoundary {
  dataScope: string;
  privacyMode: string;

  constructor(dataScope: string, privacyMode: string) {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
  }
}

/** Owns explicit Bookmark management reads, mutations, and HTML transfer effects. */
export class BookmarkManagementFeature {
  private readonly bookmarksFeature: BookmarksFeature;
  private readonly mutationService: BookmarkMutationService;
  private readonly htmlTransferService: BookmarkHtmlTransferService;
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService;
  private boundary?: BookmarkManagementBoundary;
  private scope?: BookmarkStorageScope;

  constructor(
    bookmarksFeature: BookmarksFeature,
    mutationService: BookmarkMutationService,
    htmlTransferService: BookmarkHtmlTransferService = new BookmarkHtmlTransferService(),
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.bookmarksFeature = bookmarksFeature;
    this.mutationService = mutationService;
    this.htmlTransferService = htmlTransferService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  configure(boundary: BookmarkManagementBoundary, scope: BookmarkStorageScope): void {
    this.boundary = boundary;
    this.scope = scope;
    this.bookmarksFeature.setScope(scope);
  }

  refresh(): Promise<BookmarkNode[]> {
    this.assertReadAllowed();
    return this.bookmarksFeature.refresh();
  }

  listPreviewChildren(parentId: string | undefined, limit: number): Promise<BookmarkNode[]> {
    this.assertReadAllowed();
    return this.bookmarksFeature.listPreviewChildren(parentId, limit);
  }

  listDisplayChildren(parentId?: string): BookmarkNode[] {
    this.assertReadAllowed();
    return this.bookmarksFeature.listDisplayChildren(parentId);
  }

  getSnapshot(includeDeleted: boolean = false): BookmarkRepositorySnapshot {
    this.assertReadAllowed();
    return this.bookmarksFeature.getSnapshot(includeDeleted);
  }

  findNodeById(id: string, includeDeleted: boolean = false): BookmarkNode | undefined {
    this.assertReadAllowed();
    return this.bookmarksFeature.findNodeById(id, includeDeleted);
  }

  hasBookmarkForUrl(url: string): boolean {
    this.assertReadAllowed();
    return this.bookmarksFeature.hasBookmarkForUrl(url);
  }

  searchBookmarks(query: string, limit: number): BookmarkNode[] {
    this.assertReadAllowed();
    return this.bookmarksFeature.searchBookmarks(query, limit);
  }

  listSubtree(rootId: string, includeDeleted: boolean = false): BookmarkNode[] {
    this.assertReadAllowed();
    return this.bookmarksFeature.listSubtree(rootId, includeDeleted);
  }

  getPrimaryFolderId(): string | undefined {
    this.assertReadAllowed();
    return this.bookmarksFeature.getPrimaryFolderId();
  }

  buildFolderBookmarkCounts(): BookmarkFolderBookmarkCountsResult {
    this.assertReadAllowed();
    return this.bookmarksFeature.buildFolderBookmarkCounts();
  }

  buildFolderBookmarkCountsAsync(): Promise<BookmarkFolderBookmarkCountsResult> {
    this.assertReadAllowed();
    return this.bookmarksFeature.buildFolderBookmarkCountsAsync();
  }

  buildLocalBookmarkOverview(): AiraBookmarkOverview {
    this.assertReadAllowed();
    return this.bookmarksFeature.buildLocalBookmarkOverview();
  }

  buildNextFolderTitle(parentId?: string, baseTitle?: string): string {
    this.assertReadAllowed();
    return this.bookmarksFeature.buildNextFolderTitle(parentId, baseTitle);
  }

  createNode(command: BookmarkCreateNodeCommand): Promise<BookmarkNode> {
    this.assertMutationAllowed();
    return this.mutationService.createNode(command);
  }

  createRegularBookmarksIfMissing(commands: BookmarkCreateNodeCommand[]): Promise<BookmarkNode[]> {
    this.assertRegularScope();
    this.assertMutationAllowed();
    return this.mutationService.createBookmarksIfMissing(commands);
  }

  moveSubtrees(command: BookmarkMoveSubtreesCommand): Promise<BookmarkNode[]> {
    this.assertMutationAllowed();
    return this.mutationService.moveSubtrees(command);
  }

  reorderChildren(command: BookmarkReorderChildrenCommand): Promise<BookmarkNode[]> {
    this.assertMutationAllowed();
    return this.mutationService.reorderChildren(command);
  }

  beginUpdateNode(command: UpdateBookmarkCommand): BookmarkUpdateNodeOperation {
    this.assertMutationAllowed();
    return this.mutationService.beginUpdateNode(command);
  }

  updateNode(command: UpdateBookmarkCommand): Promise<BookmarkNode | undefined> {
    this.assertMutationAllowed();
    return this.mutationService.updateNode(command);
  }

  deleteNode(nodeId: string): Promise<boolean> {
    this.assertMutationAllowed();
    return this.mutationService.deleteNode(nodeId);
  }

  deleteNodes(nodeIds: string[]): Promise<number> {
    this.assertMutationAllowed();
    return this.mutationService.deleteNodes(nodeIds);
  }

  deleteRegularBookmarksByUrls(urls: string[]): Promise<number> {
    this.assertRegularScope();
    this.assertMutationAllowed();
    return this.mutationService.deleteBookmarksByUrls(urls);
  }

  applyHtmlImport(payload: string): Promise<AiraBookmarkImportApplyResult> {
    this.assertMutationAllowed();
    const plan = this.htmlTransferService.decode(payload);
    return this.mutationService.applyImportPlan(plan, this.requireScope(), {
      sourceType: 'chrome_html',
      providerId: 'import_export',
      sourceLabel: '浏览器书签 HTML'
    });
  }

  buildHtmlExport(): string {
    this.assertExportAllowed();
    return this.htmlTransferService.encode(this.getSnapshot(false).nodes);
  }

  authorizeNavigation(): void {
    const scope = this.requireScope();
    if (scope === 'private') {
      this.assertReadAllowed();
      return;
    }
    this.assertCatalogEffectAllowed(
      'regular_profile_management_navigation',
      'regular_profile_data'
    );
  }

  authorizeShare(): void {
    const scope = this.requireScope();
    this.assertCatalogEffectAllowed(
      scope === 'private' ? 'private_bookmark_share' : 'regular_profile_management_share',
      scope === 'private' ? 'user_selected_external_location' : 'regular_profile_data'
    );
  }

  private assertReadAllowed(): void {
    if (!this.isEffectAllowed('read')) {
      throw new Error('Bookmark management read privacy effect was not allowed.');
    }
  }

  private assertMutationAllowed(): void {
    if (!this.isEffectAllowed('mutation')) {
      throw new Error('Bookmark management mutation privacy effect was not allowed.');
    }
  }

  private assertExportAllowed(): void {
    if (!this.isEffectAllowed('export')) {
      throw new Error('Bookmark management export privacy effect was not allowed.');
    }
  }

  private assertCatalogEffectAllowed(
    intent: 'regular_profile_management_navigation' | 'regular_profile_management_share' | 'private_bookmark_share',
    targetScope: 'regular_profile_data' | 'user_selected_external_location'
  ): void {
    const boundary = this.requireBoundary();
    const requestingBoundary = this.profileBoundaryService.buildBoundary({
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode
    });
    if (this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: targetScope,
      targetIsClear: true
    }).outcome !== 'allow') {
      throw new Error('Bookmark management privacy effect was not allowed.');
    }
  }

  private isEffectAllowed(effect: 'read' | 'mutation' | 'export'): boolean {
    const boundary = this.requireBoundary();
    const scope = this.requireScope();
    const requestingBoundary = this.profileBoundaryService.buildBoundary({
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode
    });
    if (effect === 'export') {
      return this.privacyEffectPolicy.decide({
        intent: scope === 'private' ? 'private_bookmark_export' : 'regular_profile_management_export',
        requestingBoundary: requestingBoundary,
        targetScope: 'user_selected_external_location',
        targetIsClear: true
      }).outcome === 'allow';
    }
    if (scope === 'private') {
      const policy = this.privacyEffectPolicy.resolveDataPolicyForBoundary('private_bookmarks', requestingBoundary);
      return effect === 'read' ? policy.persistentReadAllowed : policy.persistentWriteAllowed;
    }
    const intent = effect === 'read' ?
      'regular_profile_management_read' : 'regular_profile_management_mutation';
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: 'regular_profile_data',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private requireBoundary(): BookmarkManagementBoundary {
    if (this.boundary === undefined) {
      throw new Error('Bookmark management boundary is required.');
    }
    return this.boundary;
  }

  private requireScope(): BookmarkStorageScope {
    if (this.scope === undefined) {
      throw new Error('Bookmark management scope is required.');
    }
    return this.scope;
  }

  private assertRegularScope(): void {
    if (this.requireScope() !== 'regular') {
      throw new Error('Regular Bookmark management scope is required.');
    }
  }
}
