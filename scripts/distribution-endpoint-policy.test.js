'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { isLocalTestMode, parseEndpoint } = require('./distribution-endpoint-policy');

test('accepts a normal HTTPS endpoint and removes fragment/trailing slash', () => {
  assert.equal(parseEndpoint('https://api.example.test/v1/#ignored', { label: 'route' }), 'https://api.example.test/v1');
});

test('rejects HTTP unless local test mode explicitly enables it', () => {
  assert.throws(() => parseEndpoint('http://192.168.1.2:19000', { label: 'route' }), /HTTPS URL/);
  assert.equal(
    parseEndpoint('http://192.168.1.2:19000/', { allowHttp: true, label: 'route' }),
    'http://192.168.1.2:19000'
  );
});

test('rejects credentials and non-absolute endpoints in every mode', () => {
  assert.throws(() => parseEndpoint('https://user:pass@example.test', { label: 'route' }), /without credentials/);
  assert.throws(() => parseEndpoint('/sync/v4/bookmarks', { allowHttp: true, label: 'route' }), /absolute/);
});

test('recognizes only explicit local test values', () => {
  assert.equal(isLocalTestMode('1'), true);
  assert.equal(isLocalTestMode('true'), true);
  assert.equal(isLocalTestMode('0'), false);
  assert.equal(isLocalTestMode(''), false);
});
