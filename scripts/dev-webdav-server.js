#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const host = process.env.WEBDAV_HOST || '0.0.0.0';
const port = Number(process.env.WEBDAV_PORT || 8787);
const username = process.env.WEBDAV_USERNAME || '1';
const password = process.env.WEBDAV_PASSWORD || '1';
const ignoreIfNoneMatch = process.env.WEBDAV_IGNORE_IF_NONE_MATCH === '1';
const conflictOnMissingParent = process.env.WEBDAV_CONFLICT_ON_MISSING_PARENT === '1';
const rootDir = path.resolve(process.env.WEBDAV_ROOT || path.join(process.cwd(), '.tmp-sync-lab', 'webdav-root'));

fs.mkdirSync(rootDir, { recursive: true });

function encodeXml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function isAuthorized(request) {
  const header = request.headers.authorization || '';
  if (!header.startsWith('Basic ')) {
    return false;
  }
  const decoded = Buffer.from(header.slice('Basic '.length), 'base64').toString('utf8');
  return decoded === `${username}:${password}`;
}

function sendUnauthorized(response) {
  response.writeHead(401, {
    'WWW-Authenticate': 'Basic realm="Aira WebDAV"',
    'Content-Type': 'text/plain; charset=utf-8',
  });
  response.end('Authentication required.');
}

function normalizeRequestPath(requestUrl) {
  const url = new URL(requestUrl, 'http://localhost');
  const rawPath = decodeURIComponent(url.pathname);
  const normalized = path.normalize(rawPath).replace(/^(\.\.[/\\])+/, '');
  const relative = normalized.replace(/^[/\\]+/, '');
  const resolved = path.resolve(rootDir, relative);
  if (resolved !== rootDir && !resolved.startsWith(`${rootDir}${path.sep}`)) {
    throw new Error('Path escapes WebDAV root.');
  }
  return {
    href: rawPath.endsWith('/') ? rawPath : `/${relative}`,
    fsPath: resolved,
    relativePath: relative,
  };
}

function readRequestBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on('data', (chunk) => chunks.push(chunk));
    request.on('end', () => resolve(Buffer.concat(chunks)));
    request.on('error', reject);
  });
}

function writeEmpty(response, status, headers = {}) {
  response.writeHead(status, headers);
  response.end();
}

function contentTypeFor(filePath) {
  if (filePath.endsWith('.json')) {
    return 'application/json; charset=utf-8';
  }
  if (filePath.endsWith('.txt') || filePath.endsWith('.log')) {
    return 'text/plain; charset=utf-8';
  }
  return 'application/octet-stream';
}

function buildFileEtag(filePath) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    return '';
  }
  const digest = crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
  return `"${digest}"`;
}

function deleteRecursive(targetPath) {
  if (!fs.existsSync(targetPath)) {
    return;
  }
  const stat = fs.statSync(targetPath);
  if (stat.isDirectory()) {
    fs.rmSync(targetPath, { recursive: true, force: true });
    return;
  }
  fs.unlinkSync(targetPath);
}

function hasExistingParentCollection(targetPath) {
  if (targetPath === rootDir) {
    return true;
  }
  const parentPath = path.dirname(targetPath);
  return fs.existsSync(parentPath) && fs.statSync(parentPath).isDirectory();
}

function buildPropstat(href, fsPath, stat) {
  const isDirectory = stat.isDirectory();
  const safeHref = encodeXml(href);
  const lastModified = stat.mtime.toUTCString();
  const length = isDirectory ? 0 : stat.size;
  const resourceType = isDirectory ? '<D:collection/>' : '';
  const etag = isDirectory ? '' : buildFileEtag(fsPath);
  return [
    '  <D:response>',
    `    <D:href>${safeHref}</D:href>`,
    '    <D:propstat>',
    '      <D:prop>',
    `        <D:displayname>${encodeXml(path.basename(fsPath) || '/')}</D:displayname>`,
    `        <D:getlastmodified>${encodeXml(lastModified)}</D:getlastmodified>`,
    `        <D:getcontentlength>${length}</D:getcontentlength>`,
    `        <D:getetag>${encodeXml(etag)}</D:getetag>`,
    `        <D:resourcetype>${resourceType}</D:resourcetype>`,
    '      </D:prop>',
    '      <D:status>HTTP/1.1 200 OK</D:status>',
    '    </D:propstat>',
    '  </D:response>',
  ].join('\n');
}

function buildPropfindXml(target, depth) {
  const entries = [];
  const targetStat = fs.statSync(target.fsPath);
  const targetHref = target.relativePath.length === 0 ? '/' : `/${target.relativePath}${targetStat.isDirectory() ? '/' : ''}`;
  entries.push(buildPropstat(targetHref, target.fsPath, targetStat));
  if (targetStat.isDirectory() && depth !== '0') {
    const children = fs.readdirSync(target.fsPath).sort();
    children.forEach((child) => {
      const childPath = path.join(target.fsPath, child);
      const childStat = fs.statSync(childPath);
      const childRelative = path.posix.join('/', target.relativePath.replace(/\\/g, '/'), child);
      entries.push(buildPropstat(`${childRelative}${childStat.isDirectory() ? '/' : ''}`, childPath, childStat));
    });
  }
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<D:multistatus xmlns:D="DAV:">',
    entries.join('\n'),
    '</D:multistatus>',
  ].join('\n');
}

function listNetworkUrls() {
  const urls = [`http://127.0.0.1:${port}/`];
  Object.values(os.networkInterfaces()).forEach((items) => {
    (items || []).forEach((item) => {
      if (item.family === 'IPv4' && !item.internal) {
        urls.push(`http://${item.address}:${port}/`);
      }
    });
  });
  return Array.from(new Set(urls));
}

async function handleRequest(request, response) {
  try {
    if (!isAuthorized(request)) {
      sendUnauthorized(response);
      return;
    }
    const target = normalizeRequestPath(request.url || '/');
    if (request.method === 'OPTIONS') {
      response.writeHead(200, {
        DAV: '1, 2',
        Allow: 'OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, PROPFIND',
        'MS-Author-Via': 'DAV',
      });
      response.end();
      return;
    }
    if (request.method === 'MKCOL') {
      if (fs.existsSync(target.fsPath)) {
        writeEmpty(response, 405);
        return;
      }
      if (conflictOnMissingParent && !hasExistingParentCollection(target.fsPath)) {
        writeEmpty(response, 409);
        return;
      }
      fs.mkdirSync(target.fsPath, { recursive: !conflictOnMissingParent });
      writeEmpty(response, 201);
      return;
    }
    if (request.method === 'PUT') {
      const existed = fs.existsSync(target.fsPath);
      if (!existed && conflictOnMissingParent && !hasExistingParentCollection(target.fsPath)) {
        writeEmpty(response, 409);
        return;
      }
      const currentEtag = existed ? buildFileEtag(target.fsPath) : '';
      const ifNoneMatch = String(request.headers['if-none-match'] || '').trim();
      if (!ignoreIfNoneMatch && ifNoneMatch === '*' && existed) {
        writeEmpty(response, 412);
        return;
      }
      const ifMatch = String(request.headers['if-match'] || '').trim();
      if (ifMatch && (!existed || ifMatch !== currentEtag)) {
        writeEmpty(response, 412);
        return;
      }
      fs.mkdirSync(path.dirname(target.fsPath), { recursive: true });
      const body = await readRequestBody(request);
      fs.writeFileSync(target.fsPath, body);
      writeEmpty(response, existed ? 204 : 201, {
        ETag: buildFileEtag(target.fsPath),
      });
      return;
    }
    if (request.method === 'MOVE') {
      if (!fs.existsSync(target.fsPath)) {
        writeEmpty(response, 404);
        return;
      }
      const destinationHeader = String(request.headers.destination || '').trim();
      if (destinationHeader.length <= 0) {
        writeEmpty(response, 400);
        return;
      }
      const destination = normalizeRequestPath(destinationHeader);
      const destinationExists = fs.existsSync(destination.fsPath);
      const overwrite = String(request.headers.overwrite || 'T').trim().toUpperCase();
      if (destinationExists && overwrite === 'F') {
        writeEmpty(response, 412);
        return;
      }
      if (!fs.existsSync(path.dirname(destination.fsPath))) {
        writeEmpty(response, 409);
        return;
      }
      if (destinationExists) {
        deleteRecursive(destination.fsPath);
      }
      fs.renameSync(target.fsPath, destination.fsPath);
      writeEmpty(response, destinationExists ? 204 : 201, {
        ETag: buildFileEtag(destination.fsPath),
      });
      return;
    }
    if (request.method === 'DELETE') {
      if (!fs.existsSync(target.fsPath)) {
        writeEmpty(response, 404);
        return;
      }
      deleteRecursive(target.fsPath);
      writeEmpty(response, 204);
      return;
    }
    if (request.method === 'PROPFIND') {
      if (!fs.existsSync(target.fsPath)) {
        writeEmpty(response, 404);
        return;
      }
      const depth = String(request.headers.depth || '1');
      const xml = buildPropfindXml(target, depth);
      response.writeHead(207, {
        'Content-Type': 'application/xml; charset=utf-8',
        'Content-Length': Buffer.byteLength(xml),
      });
      response.end(xml);
      return;
    }
    if (request.method === 'GET' || request.method === 'HEAD') {
      if (!fs.existsSync(target.fsPath)) {
        writeEmpty(response, conflictOnMissingParent && !hasExistingParentCollection(target.fsPath) ? 409 : 404);
        return;
      }
      const stat = fs.statSync(target.fsPath);
      if (stat.isDirectory()) {
        const children = fs.readdirSync(target.fsPath).sort();
        const text = `${children.join('\n')}${children.length > 0 ? '\n' : ''}`;
        response.writeHead(200, {
          'Content-Type': 'text/plain; charset=utf-8',
          'Content-Length': Buffer.byteLength(text),
        });
        response.end(request.method === 'HEAD' ? undefined : text);
        return;
      }
      response.writeHead(200, {
        'Content-Type': contentTypeFor(target.fsPath),
        'Content-Length': stat.size,
        'Last-Modified': stat.mtime.toUTCString(),
        ETag: buildFileEtag(target.fsPath),
      });
      if (request.method === 'HEAD') {
        response.end();
        return;
      }
      fs.createReadStream(target.fsPath).pipe(response);
      return;
    }
    writeEmpty(response, 405, { Allow: 'OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, PROPFIND' });
  } catch (error) {
    response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end(error && error.message ? error.message : String(error));
  }
}

const server = http.createServer((request, response) => {
  void handleRequest(request, response);
});

server.listen(port, host, () => {
  console.log(`Aira dev WebDAV root: ${rootDir}`);
  console.log(`Aira dev WebDAV user/pass: ${username}/${password}`);
  console.log(`Aira dev WebDAV ignores If-None-Match: ${ignoreIfNoneMatch ? 'yes' : 'no'}`);
  console.log(`Aira dev WebDAV conflicts on missing parent: ${conflictOnMissingParent ? 'yes' : 'no'}`);
  console.log('Aira dev WebDAV URLs:');
  listNetworkUrls().forEach((url) => console.log(`  ${url}`));
});
