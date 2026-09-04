function normalize(value) {
  return String(value ?? '').trim();
}

function resolveHuaweiAppIdentity(agconnect, requestedAppId = '', requestedClientId = '') {
  const appId = normalize(requestedAppId) ||
    normalize(agconnect?.client?.app_id) ||
    normalize(agconnect?.app_info?.app_id);
  const clientId = normalize(requestedClientId) ||
    normalize(agconnect?.oauth_client?.client_id) ||
    appId;
  return {
    appId,
    clientId
  };
}

module.exports = {
  resolveHuaweiAppIdentity
};
