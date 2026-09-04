'use strict';

function parseEndpoint(value, { allowHttp = false, label = 'endpoint' } = {}) {
  const raw = String(value || '').trim();
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`${label} must be an absolute HTTPS URL${allowHttp ? ' or HTTP URL in local test mode' : ''}.`);
  }
  const allowedProtocols = allowHttp ? new Set(['https:', 'http:']) : new Set(['https:']);
  if (!allowedProtocols.has(url.protocol) || url.username || url.password) {
    throw new Error(`${label} must be an ${allowHttp ? 'HTTPS or HTTP' : 'HTTPS'} URL without credentials.`);
  }
  url.hash = '';
  return url.toString().replace(/\/$/, '');
}

function isLocalTestMode(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').trim().toLowerCase());
}

module.exports = { isLocalTestMode, parseEndpoint };
