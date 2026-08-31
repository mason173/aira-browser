import { BookmarkNode } from '../../common/models/BrowserModels';
import { AiraBookmarkImportNode, AiraBookmarkImportPlan } from '../../common/models/AiraSyncModels';

const BOOKMARK_HTML_TITLE: string = 'Aira Bookmarks';
const IMPORT_ROOT_ID: string = 'html-root';

interface BookmarkHtmlStackEntry {
  id: string;
  title: string;
}

interface BookmarkHtmlImportCounters {
  nextId: number;
  positionByParent: Record<string, number>;
}

export class BookmarkHtmlTransferService {
  encode(nodes: BookmarkNode[]): string {
    const activeNodes = nodes
      .filter((node: BookmarkNode) => node.sync.deletedAt === undefined)
      .slice()
      .sort((left: BookmarkNode, right: BookmarkNode) => {
        const leftParent = left.parentId ?? '';
        const rightParent = right.parentId ?? '';
        if (leftParent !== rightParent) {
          return leftParent.localeCompare(rightParent);
        }
        return left.position - right.position;
      });
    const lines: string[] = [
      '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
      `<TITLE>${BOOKMARK_HTML_TITLE}</TITLE>`,
      '<H1>Bookmarks</H1>',
      '<DL><p>'
    ];
    this.appendChildren(lines, activeNodes, undefined, 1);
    lines.push('</DL><p>');
    return lines.join('\n');
  }

  decode(payload: string): AiraBookmarkImportPlan {
    const nodes: AiraBookmarkImportNode[] = [];
    const rootOrderIds: string[] = [];
    const stack: BookmarkHtmlStackEntry[] = [];
    const counters: BookmarkHtmlImportCounters = {
      nextId: 1,
      positionByParent: {}
    };
    let pendingFolder: BookmarkHtmlStackEntry | undefined = undefined;
    let folderCount = 0;
    let bookmarkCount = 0;
    this.scanNonEmptyLines(payload, (trimmed: string): void => {
      if (this.isHeading(trimmed)) {
        const title = this.decodeHtml(this.extractElementText(trimmed, '<H3', '</H3>'));
        const id = this.nextImportId(counters, 'folder');
        const parentId = this.currentParentId(stack);
        nodes.push(this.buildImportNode(id, 'folder', title.length > 0 ? title : '导入文件夹', parentId, '', counters));
        if (parentId === undefined) {
          rootOrderIds.push(id);
        }
        folderCount += 1;
        pendingFolder = { id: id, title: title };
        return;
      }
      if (this.isBookmark(trimmed)) {
        const title = this.decodeHtml(this.extractElementText(trimmed, '<A', '</A>'));
        const url = this.extractAttribute(trimmed, 'HREF');
        if (url.trim().length <= 0) {
          return;
        }
        const id = this.nextImportId(counters, 'bookmark');
        const parentId = this.currentParentId(stack);
        nodes.push(this.buildImportNode(id, 'bookmark', title.length > 0 ? title : url, parentId,
          this.decodeHtml(url), counters));
        if (parentId === undefined) {
          rootOrderIds.push(id);
        }
        bookmarkCount += 1;
        return;
      }
      if (this.startsWithIgnoreCase(trimmed, '<DL')) {
        if (pendingFolder !== undefined) {
          stack.push(pendingFolder);
          pendingFolder = undefined;
        }
        return;
      }
      if (this.startsWithIgnoreCase(trimmed, '</DL')) {
        if (stack.length > 0) {
          stack.pop();
        }
        pendingFolder = undefined;
      }
    });
    return {
      nodes: nodes,
      rootOrderIds: rootOrderIds,
      summary: `HTML 书签文件包含 ${folderCount} 个文件夹、${bookmarkCount} 个书签。`
    };
  }

  private appendChildren(lines: string[], nodes: BookmarkNode[], parentId: string | undefined, depth: number): void {
    const children = nodes
      .filter((node: BookmarkNode) => node.parentId === parentId)
      .sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
    children.forEach((node: BookmarkNode) => {
      const indent = this.indent(depth);
      const addDate = Math.floor(node.createdAt / 1000);
      if (node.type === 'folder') {
        lines.push(`${indent}<DT><H3 ADD_DATE="${addDate}">${this.escapeHtml(node.title)}</H3>`);
        lines.push(`${indent}<DL><p>`);
        this.appendChildren(lines, nodes, node.id, depth + 1);
        lines.push(`${indent}</DL><p>`);
      } else {
        lines.push(`${indent}<DT><A HREF="${this.escapeHtml(node.url ?? '')}" ADD_DATE="${addDate}">${this.escapeHtml(node.title)}</A>`);
      }
    });
  }

  private scanNonEmptyLines(payload: string, visit: (line: string) => void): void {
    let lineStart = 0;
    let index = 0;
    while (index < payload.length) {
      const code = payload.charCodeAt(index);
      if (code === 10 || code === 13) {
        this.visitTrimmedLine(payload, lineStart, index, visit);
        if (code === 13 && index + 1 < payload.length && payload.charCodeAt(index + 1) === 10) {
          index += 1;
        }
        lineStart = index + 1;
      }
      index += 1;
    }
    if (lineStart < payload.length) {
      this.visitTrimmedLine(payload, lineStart, payload.length, visit);
    }
  }

  private visitTrimmedLine(payload: string, start: number, end: number, visit: (line: string) => void): void {
    const trimmed = payload.substring(start, end).trim();
    if (trimmed.length > 0) {
      visit(trimmed);
    }
  }

  private isHeading(token: string): boolean {
    return this.indexOfIgnoreCase(token, '<H3') >= 0 && this.indexOfIgnoreCase(token, '</H3>') >= 0;
  }

  private isBookmark(token: string): boolean {
    return this.indexOfIgnoreCase(token, '<A ') >= 0 &&
      this.indexOfIgnoreCase(token, 'HREF=') >= 0 &&
      this.indexOfIgnoreCase(token, '</A>') >= 0;
  }

  private buildImportNode(
    id: string,
    type: 'folder' | 'bookmark',
    title: string,
    parentId: string | undefined,
    url: string,
    counters: BookmarkHtmlImportCounters
  ): AiraBookmarkImportNode {
    const parentKey = parentId ?? IMPORT_ROOT_ID;
    const position = counters.positionByParent[parentKey] ?? 0;
    counters.positionByParent[parentKey] = position + 1;
    const now = Date.now();
    const node: AiraBookmarkImportNode = {
      id: id,
      type: type,
      parentId: parentId,
      title: title.trim().length > 0 ? title.trim() : (type === 'folder' ? '导入文件夹' : '未命名书签'),
      position: position,
      sourceEntityId: id,
      createdAt: now,
      updatedAt: now
    };
    if (type === 'bookmark') {
      node.url = url.trim();
    }
    return node;
  }

  private currentParentId(stack: BookmarkHtmlStackEntry[]): string | undefined {
    return stack.length > 0 ? stack[stack.length - 1].id : undefined;
  }

  private nextImportId(counters: BookmarkHtmlImportCounters, prefix: string): string {
    const id = `html-${prefix}-${counters.nextId}`;
    counters.nextId += 1;
    return id;
  }

  private extractAttribute(token: string, attributeName: string): string {
    let searchStart = 0;
    while (searchStart < token.length) {
      const attributeIndex = this.indexOfIgnoreCase(token, attributeName, searchStart);
      if (attributeIndex < 0) {
        return '';
      }
      let index = attributeIndex + attributeName.length;
      while (index < token.length && this.isWhitespace(token.charCodeAt(index))) {
        index += 1;
      }
      if (index >= token.length || token.charAt(index) !== '=') {
        searchStart = attributeIndex + attributeName.length;
        continue;
      }
      index += 1;
      while (index < token.length && this.isWhitespace(token.charCodeAt(index))) {
        index += 1;
      }
      if (index >= token.length) {
        return '';
      }
      const quote = token.charAt(index);
      if (quote === '"' || quote === "'") {
        const valueStart = index + 1;
        const valueEnd = token.indexOf(quote, valueStart);
        return valueEnd < 0 ? token.substring(valueStart) : token.substring(valueStart, valueEnd);
      }
      const valueStart = index;
      while (index < token.length && !this.isWhitespace(token.charCodeAt(index)) && token.charAt(index) !== '>') {
        index += 1;
      }
      return token.substring(valueStart, index);
    }
    return '';
  }

  private extractElementText(token: string, openingTag: string, closingTag: string): string {
    const openIndex = this.indexOfIgnoreCase(token, openingTag);
    if (openIndex < 0) {
      return '';
    }
    const contentStart = token.indexOf('>', openIndex);
    if (contentStart < 0) {
      return '';
    }
    const contentEnd = this.indexOfIgnoreCase(token, closingTag, contentStart + 1);
    if (contentEnd <= contentStart) {
      return '';
    }
    return token.substring(contentStart + 1, contentEnd).trim();
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  private decodeHtml(value: string): string {
    return value
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  private indent(depth: number): string {
    return '    '.repeat(Math.max(0, depth));
  }

  private startsWithIgnoreCase(text: string, prefix: string): boolean {
    return this.matchesIgnoreCaseAt(text, prefix, 0);
  }

  private indexOfIgnoreCase(text: string, search: string, fromIndex: number = 0): number {
    if (search.length === 0) {
      return Math.max(0, Math.min(fromIndex, text.length));
    }
    const start = Math.max(0, fromIndex);
    const limit = text.length - search.length;
    for (let index = start; index <= limit; index += 1) {
      if (this.matchesIgnoreCaseAt(text, search, index)) {
        return index;
      }
    }
    return -1;
  }

  private matchesIgnoreCaseAt(text: string, search: string, start: number): boolean {
    if (start < 0 || start + search.length > text.length) {
      return false;
    }
    for (let offset = 0; offset < search.length; offset += 1) {
      if (this.toLowerAsciiCode(text.charCodeAt(start + offset)) !==
        this.toLowerAsciiCode(search.charCodeAt(offset))) {
        return false;
      }
    }
    return true;
  }

  private toLowerAsciiCode(code: number): number {
    return code >= 65 && code <= 90 ? code + 32 : code;
  }

  private isWhitespace(code: number): boolean {
    return code === 32 || code === 9 || code === 10 || code === 13 || code === 12;
  }
}
