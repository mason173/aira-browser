#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const DEFAULT_COUNT = 10000;
const DEFAULT_OUTPUT = '.tmp-bookmark-import/bookmarks-10000-complex.html';
const ROOT_FOLDERS = ['Bookmarks Bar', 'Other Bookmarks', 'Mobile Bookmarks'];
const SECTION_NAMES = [
  '工作台', '学习资料', '技术文档', '设计参考', '影音娱乐', '购物比价',
  '旅行计划', '家庭资料', '金融票据', '临时收藏', 'Archive', 'Research'
];
const TOPIC_NAMES = [
  'ArkUI', 'HarmonyOS NEXT', 'Browser', 'Sync', 'Reader Mode', 'AI Tools',
  'Database', 'Performance', 'News', 'Maps', 'Recipe', 'Photography'
];
const SITE_HOSTS = [
  'docs.example.test',
  'news.example.test',
  'tools.example.test',
  'notes.example.test',
  'shop.example.test',
  'media.example.test',
  'dev.example.test',
  'sync.example.test'
];

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

function indent(depth) {
  return '    '.repeat(depth);
}

function dateFor(index) {
  return String(1710000000 + index);
}

function folderTitle(folderIndex, depth, branch) {
  const section = SECTION_NAMES[(folderIndex + branch) % SECTION_NAMES.length];
  const topic = TOPIC_NAMES[(folderIndex * 3 + depth) % TOPIC_NAMES.length];
  const suffixes = [
    `L${depth}`,
    `第 ${String(folderIndex).padStart(4, '0')} 组`,
    `Inbox & Review`,
    `2026/Q${(folderIndex % 4) + 1}`,
    `Nested-${branch}`
  ];
  return `${section} / ${topic} / ${suffixes[folderIndex % suffixes.length]}`;
}

function bookmarkTitle(index, depth, folderIndex) {
  const section = SECTION_NAMES[(index + folderIndex) % SECTION_NAMES.length];
  const topic = TOPIC_NAMES[(index * 7 + depth) % TOPIC_NAMES.length];
  const variants = [
    '首页',
    '文章 & 评论',
    '深度链接',
    '带查询参数',
    '临时待读',
    '收藏: 重要'
  ];
  return `${String(index).padStart(5, '0')} - ${section} - ${topic} - ${variants[index % variants.length]}`;
}

function bookmarkUrl(index, depth, folderIndex) {
  const host = SITE_HOSTS[index % SITE_HOSTS.length];
  const section = encodeURIComponent(SECTION_NAMES[(index + folderIndex) % SECTION_NAMES.length]);
  const topic = encodeURIComponent(TOPIC_NAMES[(index * 7 + depth) % TOPIC_NAMES.length]);
  const pathKind = index % 6;
  if (pathKind === 0) {
    return `https://${host}/spaces/${section}/items/${index}?from=aira&depth=${depth}&folder=${folderIndex}`;
  }
  if (pathKind === 1) {
    return `https://${host}/docs/${topic}/${String(index).padStart(5, '0')}#section-${depth}`;
  }
  if (pathKind === 2) {
    return `https://${host}/search?q=${topic}&page=${index % 37}&sort=updated&id=${index}`;
  }
  if (pathKind === 3) {
    return `https://${host}/u/tester-${folderIndex}/collection/${index}?tags=${section},${topic}`;
  }
  if (pathKind === 4) {
    return `https://${host}/deep/a/b/c/d/e/${index}/index.html?utm_source=bookmark-import`;
  }
  return `https://${host}/mixed/${section}/${topic}/${index}?emoji=%E2%9C%85&safe=1`;
}

function pushFolderOpen(lines, title, depth, addDateIndex) {
  lines.push(`${indent(depth)}<DT><H3 ADD_DATE="${dateFor(addDateIndex)}">${escapeHtml(title)}</H3>`);
  lines.push(`${indent(depth)}<DL><p>`);
}

function pushFolderClose(lines, depth) {
  lines.push(`${indent(depth)}</DL><p>`);
}

function pushBookmark(lines, index, depth, folderIndex) {
  lines.push(
    `${indent(depth)}<DT><A HREF="${escapeHtml(bookmarkUrl(index, depth, folderIndex))}" ` +
      `ADD_DATE="${dateFor(index)}">${escapeHtml(bookmarkTitle(index, depth, folderIndex))}</A>`
  );
}

function buildTreePlan() {
  const folders = [];
  let folderIndex = 0;
  for (let rootIndex = 0; rootIndex < ROOT_FOLDERS.length; rootIndex += 1) {
    for (let sectionIndex = 0; sectionIndex < 14; sectionIndex += 1) {
      folderIndex += 1;
      const sectionDepth = 2;
      const sectionId = folderIndex;
      folders.push({
        id: sectionId,
        parentId: 0,
        rootIndex,
        path: [folderTitle(folderIndex, sectionDepth, rootIndex)],
        depth: sectionDepth
      });
      const topicCount = 3 + ((sectionIndex + rootIndex) % 5);
      for (let topicIndex = 0; topicIndex < topicCount; topicIndex += 1) {
        folderIndex += 1;
        const topicDepth = 3;
        const topicId = folderIndex;
        const topicPath = folders[folders.length - 1].path.concat(folderTitle(folderIndex, topicDepth, topicIndex));
        folders.push({
          id: topicId,
          parentId: sectionId,
          rootIndex,
          path: topicPath,
          depth: topicDepth
        });
        const deepCount = 1 + ((topicIndex + sectionIndex) % 4);
        let deepPath = topicPath;
        let parentId = topicId;
        for (let deepIndex = 0; deepIndex < deepCount; deepIndex += 1) {
          folderIndex += 1;
          const deepDepth = 4 + deepIndex;
          deepPath = deepPath.concat(folderTitle(folderIndex, deepDepth, deepIndex));
          const deepId = folderIndex;
          folders.push({
            id: deepId,
            parentId,
            rootIndex,
            path: deepPath,
            depth: deepDepth
          });
          parentId = deepId;
        }
      }
    }
  }
  return folders;
}

function allocateBookmarks(count, folders) {
  const allocations = new Map();
  let remaining = count;
  let weightedTotal = 0;
  const weights = folders.map((folder) => {
    const depthWeight = Math.max(1, folder.depth - 1);
    const burst = folder.id % 17 === 0 ? 9 : folder.id % 11 === 0 ? 5 : 1;
    const sparse = folder.id % 13 === 0 ? 0 : 1;
    const weight = sparse * (depthWeight + burst + (folder.id % 4));
    weightedTotal += weight;
    return weight;
  });

  folders.forEach((folder, index) => {
    const value = weights[index] === 0 ? 0 : Math.floor((count * weights[index]) / weightedTotal);
    allocations.set(folder.id, value);
    remaining -= value;
  });

  let cursor = 0;
  while (remaining > 0) {
    const folder = folders[cursor % folders.length];
    if (weights[cursor % folders.length] > 0) {
      allocations.set(folder.id, (allocations.get(folder.id) ?? 0) + 1);
      remaining -= 1;
    }
    cursor += 1;
  }

  return allocations;
}

function buildNestedFolder(lines, folder, childGroups, allocations, state, depth) {
  pushFolderOpen(lines, folder.path[folder.path.length - 1], depth, 50000 + folder.id);
  const bookmarkCount = allocations.get(folder.id) ?? 0;
  const firstSlice = Math.ceil(bookmarkCount * 0.35);
  for (let index = 0; index < firstSlice; index += 1) {
    state.bookmarkIndex += 1;
    pushBookmark(lines, state.bookmarkIndex, depth + 1, folder.id);
  }

  const children = childGroups.get(folder.id) ?? [];
  children.forEach((child) => buildNestedFolder(lines, child, childGroups, allocations, state, depth + 1));

  if (folder.id % 19 === 0) {
    pushFolderOpen(lines, `空文件夹 / Empty ${String(folder.id).padStart(4, '0')}`, depth + 1, 80000 + folder.id);
    pushFolderClose(lines, depth + 1);
  }

  for (let index = firstSlice; index < bookmarkCount; index += 1) {
    state.bookmarkIndex += 1;
    pushBookmark(lines, state.bookmarkIndex, depth + 1, folder.id);
  }
  pushFolderClose(lines, depth);
}

function buildHtml(count) {
  const folders = buildTreePlan();
  const allocations = allocateBookmarks(count, folders);
  const childGroups = new Map();
  folders.forEach((folder) => {
    const parentId = folder.parentId ?? 0;
    const children = childGroups.get(parentId) ?? [];
    children.push(folder);
    childGroups.set(parentId, children);
  });

  const lines = [
    '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
    '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
    '<TITLE>Aira Complex Bookmark Import Fixture</TITLE>',
    '<H1>Bookmarks</H1>',
    '<DL><p>'
  ];
  const state = { bookmarkIndex: 0 };
  ROOT_FOLDERS.forEach((rootTitle, rootIndex) => {
    pushFolderOpen(lines, rootTitle, 1, rootIndex + 1);
    const rootChildren = (childGroups.get(0) ?? []).filter((folder) => folder.rootIndex === rootIndex);
    rootChildren.forEach((folder) => buildNestedFolder(lines, folder, childGroups, allocations, state, 2));
    pushFolderClose(lines, 1);
  });
  lines.push('</DL><p>');
  lines.push('');

  if (state.bookmarkIndex !== count) {
    throw new Error(`Generated ${state.bookmarkIndex} bookmarks, expected ${count}.`);
  }
  return {
    html: lines.join('\n'),
    folderCount: folders.length + ROOT_FOLDERS.length + folders.filter((folder) => folder.id % 19 === 0).length
  };
}

const count = readPositiveInteger('count', DEFAULT_COUNT);
const outputPath = resolve(readOption('output', DEFAULT_OUTPUT));
const result = buildHtml(count);

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, result.html, 'utf8');

console.log(`Wrote ${count} bookmarks and ${result.folderCount} folders to ${outputPath}`);
console.log(`Size: ${Buffer.byteLength(result.html, 'utf8')} bytes`);
