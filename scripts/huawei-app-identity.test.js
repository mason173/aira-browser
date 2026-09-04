'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { resolveHuaweiAppIdentity } = require('./huawei-app-identity');

test('uses the OAuth client for Account Kit instead of the AGConnect Auth client', () => {
  const identity = resolveHuaweiAppIdentity({
    client: {
      app_id: '6917606047264922088',
      client_id: '1954626833320263296'
    },
    oauth_client: {
      client_id: '6917606047264922088'
    },
    app_info: {
      app_id: '6917606047264922088'
    }
  });

  assert.deepEqual(identity, {
    appId: '6917606047264922088',
    clientId: '6917606047264922088'
  });
});

test('falls back to the app id when an OAuth client entry is absent', () => {
  const identity = resolveHuaweiAppIdentity({
    client: {
      app_id: '123456789',
      client_id: 'agconnect-auth-client'
    }
  });

  assert.deepEqual(identity, {
    appId: '123456789',
    clientId: '123456789'
  });
});

test('honors explicit build overrides', () => {
  const identity = resolveHuaweiAppIdentity(
    {
      client: {
        app_id: 'ignored-app-id',
        client_id: 'ignored-auth-client'
      },
      oauth_client: {
        client_id: 'ignored-oauth-client'
      }
    },
    'configured-app-id',
    'configured-oauth-client'
  );

  assert.deepEqual(identity, {
    appId: 'configured-app-id',
    clientId: 'configured-oauth-client'
  });
});
