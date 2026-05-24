#!/usr/bin/env node

const http = require('http');
const fs = require('fs/promises');
const fss = require('fs');
const path = require('path');

const args = process.argv.slice(2);

const readArg = (name, fallback) => {
  const prefixed = args.find((arg) => arg.startsWith(`${name}=`));
  if (prefixed) return prefixed.slice(name.length + 1);
  const index = args.indexOf(name);
  if (index >= 0 && args[index + 1]) return args[index + 1];
  return fallback;
};

const port = Number(readArg('--port', process.env.WEBDAV_PORT || '8787')) || 8787;
const host = readArg('--host', process.env.WEBDAV_HOST || '127.0.0.1');
const root = path.resolve(readArg('--root', process.env.WEBDAV_ROOT || '.tmp-webdav-root'));

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,PUT,DELETE,MKCOL,OPTIONS,HEAD,PROPFIND',
  'Access-Control-Allow-Headers': 'Authorization,Content-Type,Depth,Overwrite,Destination,If-Match,If-None-Match',
  'Access-Control-Expose-Headers': 'Content-Length,Content-Type',
};

function send(res, status, body = '', headers = {}) {
  res.writeHead(status, { ...corsHeaders, ...headers });
  res.end(body);
}

function resolveSafePath(url) {
  const decoded = decodeURIComponent(new URL(url, `http://${host}:${port}`).pathname);
  const rel = decoded.replace(/^\/+/, '');
  const target = path.resolve(root, rel);
  if (!target.startsWith(root)) {
    throw new Error('Invalid WebDAV path');
  }
  return target;
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function main() {
  await fs.mkdir(root, { recursive: true });

  const server = http.createServer(async (req, res) => {
    try {
      const target = resolveSafePath(req.url || '/');
      const method = req.method || 'GET';
      const pathname = new URL(req.url || '/', `http://${host}:${port}`).pathname;
      console.log(`${new Date().toISOString()} ${method} ${pathname}`);

      if (method === 'OPTIONS') return send(res, 204);

      if (method === 'MKCOL') {
        await fs.mkdir(target, { recursive: true });
        return send(res, 201);
      }

      if (method === 'PUT') {
        await fs.mkdir(path.dirname(target), { recursive: true });
        const body = await readBody(req);
        await fs.writeFile(target, body);
        return send(res, 201);
      }

      if (method === 'GET' || method === 'HEAD') {
        if (!fss.existsSync(target)) return send(res, 404);
        const stat = await fs.stat(target);
        if (stat.isDirectory()) return send(res, 200, '', { 'Content-Type': 'text/plain; charset=utf-8' });
        const headers = {
          'Content-Length': String(stat.size),
          'Content-Type': 'application/json; charset=utf-8',
        };
        if (method === 'HEAD') return send(res, 200, '', headers);
        return send(res, 200, await fs.readFile(target), headers);
      }

      if (method === 'DELETE') {
        await fs.rm(target, { recursive: true, force: true });
        return send(res, 204);
      }

      if (method === 'PROPFIND') {
        return send(res, 207, '<?xml version="1.0"?><multistatus xmlns="DAV:"/>', {
          'Content-Type': 'application/xml; charset=utf-8',
        });
      }

      return send(res, 405, 'Method Not Allowed');
    } catch (error) {
      console.error(error);
      return send(res, 500, String(error?.message || error));
    }
  });

  server.listen(port, host, () => {
    console.log(`Local WebDAV test server: http://${host}:${port}/`);
    console.log(`Root: ${root}`);
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
