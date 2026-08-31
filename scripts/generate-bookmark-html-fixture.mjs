#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const DEFAULT_COUNT = 10000;
const DEFAULT_FOLDERS = 100;
const DEFAULT_OUTPUT = '.tmp-bookmark-import/bookmarks-10000.html';

function readOption(name, fallback) {
  const prefix = `--${name}=`;
  const match = process.argv.slice(2).find((argument) => argument.startsWith(prefix));
  return match === undefined ? fallback : match.slice(prefix.length);
}

function readPositiveInteger(name, fallback) {
  const raw = readOption(name, String(fallback));
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`--${name} must be a positive integer.`);
  }
  return value;
}

function escapeHtml(value) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function buildBookmarkLine(index) {
  const padded = String(index).padStart(5, '0');
  const url = `https://import-fixture.example/sites/${padded}?source=aira-large-bookmark-test`;
  const title = `Import Fixture Bookmark ${padded}`;
  return `        <DT><A HREF="${escapeHtml(url)}" ADD_DATE="171000${padded}">${escapeHtml(title)}</A>`;
}

function buildHtml(count, folderCount) {
  const safeFolderCount = Math.max(1, Math.min(folderCount, count));
  const lines = [
    '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
    '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
    '<TITLE>Aira Large Bookmark Import Fixture</TITLE>',
    '<H1>Bookmarks</H1>',
    '<DL><p>',
    '    <DT><H3 ADD_DATE="1710000000">Bookmarks Bar</H3>',
    '    <DL><p>'
  ];
  let bookmarkIndex = 0;
  for (let folderIndex = 0; folderIndex < safeFolderCount; folderIndex += 1) {
    const folderTitle = `Fixture Folder ${String(folderIndex + 1).padStart(3, '0')}`;
    lines.push(`        <DT><H3 ADD_DATE="1710000000">${escapeHtml(folderTitle)}</H3>`);
    lines.push('        <DL><p>');
    const remainingBookmarks = count - bookmarkIndex;
    const remainingFolders = safeFolderCount - folderIndex;
    const bookmarksInFolder = Math.ceil(remainingBookmarks / remainingFolders);
    for (let offset = 0; offset < bookmarksInFolder && bookmarkIndex < count; offset += 1) {
      bookmarkIndex += 1;
      lines.push(buildBookmarkLine(bookmarkIndex));
    }
    lines.push('        </DL><p>');
  }
  lines.push('    </DL><p>');
  lines.push('</DL><p>');
  lines.push('');
  return lines.join('\n');
}

const count = readPositiveInteger('count', DEFAULT_COUNT);
const folders = readPositiveInteger('folders', DEFAULT_FOLDERS);
const outputPath = resolve(readOption('output', DEFAULT_OUTPUT));
const html = buildHtml(count, folders);

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, html, 'utf8');

console.log(`Wrote ${count} bookmarks in ${Math.max(1, Math.min(folders, count))} folders to ${outputPath}`);
console.log(`Size: ${Buffer.byteLength(html, 'utf8')} bytes`);
