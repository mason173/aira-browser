export const AIRA_LOCAL_TEST_MODE: boolean = false;
export const AIRA_LOCAL_TEST_UID: string = '';
export const AIRA_LOCAL_TEST_AUTH_TOKEN: string = '';

export interface AiraLocalTestIdentity {
  uid: string;
  displayName: string;
  photoUrl: string;
  authToken: string;
}

export function resolveAiraLocalTestIdentity(): AiraLocalTestIdentity | undefined {
  if (!AIRA_LOCAL_TEST_MODE || AIRA_LOCAL_TEST_UID.trim().length <= 0 ||
    AIRA_LOCAL_TEST_AUTH_TOKEN.trim().length <= 0) {
    return undefined;
  }
  return {
    uid: AIRA_LOCAL_TEST_UID,
    displayName: `本地测试账号 ${AIRA_LOCAL_TEST_UID.slice(-6)}`,
    photoUrl: '',
    authToken: AIRA_LOCAL_TEST_AUTH_TOKEN
  };
}
