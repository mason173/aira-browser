const { bodyLimitBytes } = require('./config');
const { fail } = require('./errors');

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = '';
    let stopped = false;
    request.on('data', (chunk) => {
      if (stopped) return;
      body += chunk;
      if (Buffer.byteLength(body, 'utf8') > bodyLimitBytes) {
        stopped = true;
        reject(Object.assign(new Error('Request body is too large.'), {
          status: 413,
          code: 'request_too_large',
        }));
      }
    });
    request.on('end', () => {
      if (stopped) return;
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (_error) {
        try {
          fail(400, 'invalid_json', 'Request body must be valid JSON.');
        } catch (error) {
          reject(error);
        }
      }
    });
    request.on('error', reject);
  });
}

function writeJson(response, status, body, extraHeaders = {}) {
  const payload = status === 204 ? '' : JSON.stringify(body);
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(payload),
    ...extraHeaders,
  });
  response.end(payload);
}

module.exports = { readJson, writeJson };
