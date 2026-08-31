export type AiraLegalDocumentId =
  'user_service_agreement' |
  'privacy_statement' |
  'pro_membership_service_agreement' |
  'pro_auto_renewal_service_agreement' |
  'third_party_sdk_and_services' |
  'personal_info_and_permissions';

export interface AiraLegalDocumentLink {
  id: AiraLegalDocumentId;
  title: string;
  url: string;
}

export const AIRA_PRIVACY_STATEMENT_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1955040074076787328';

const AIRA_LEGAL_HOST: string = 'https://legal.aira.cool';

export const AIRA_USER_SERVICE_AGREEMENT_URL: string =
  `${AIRA_LEGAL_HOST}/aira-user-service-agreement.html`;
export const AIRA_PRO_MEMBERSHIP_SERVICE_AGREEMENT_URL: string =
  `${AIRA_LEGAL_HOST}/aira-pro-membership-service-agreement.html`;
export const AIRA_PRO_AUTO_RENEWAL_SERVICE_AGREEMENT_URL: string =
  `${AIRA_LEGAL_HOST}/aira-pro-auto-renewal-service-agreement.html`;
export const AIRA_THIRD_PARTY_SDK_AND_SERVICES_URL: string =
  `${AIRA_LEGAL_HOST}/aira-third-party-sdk-and-services.html`;
export const AIRA_PERSONAL_INFO_AND_PERMISSIONS_URL: string =
  `${AIRA_LEGAL_HOST}/aira-personal-info-and-permissions.html`;

export const AIRA_LEGAL_DOCUMENT_LINKS: AiraLegalDocumentLink[] = [
  {
    id: 'user_service_agreement',
    title: 'Aira用户服务协议',
    url: AIRA_USER_SERVICE_AGREEMENT_URL
  },
  {
    id: 'privacy_statement',
    title: 'Aira隐私声明',
    url: AIRA_PRIVACY_STATEMENT_URL
  },
  {
    id: 'pro_membership_service_agreement',
    title: 'Aira Pro会员服务协议',
    url: AIRA_PRO_MEMBERSHIP_SERVICE_AGREEMENT_URL
  },
  {
    id: 'pro_auto_renewal_service_agreement',
    title: 'Aira Pro自动续费服务协议',
    url: AIRA_PRO_AUTO_RENEWAL_SERVICE_AGREEMENT_URL
  },
  {
    id: 'third_party_sdk_and_services',
    title: 'Aira第三方SDK及第三方服务清单',
    url: AIRA_THIRD_PARTY_SDK_AND_SERVICES_URL
  },
  {
    id: 'personal_info_and_permissions',
    title: 'Aira个人信息收集与权限使用清单',
    url: AIRA_PERSONAL_INFO_AND_PERMISSIONS_URL
  }
];

export function resolveAiraLegalDocumentLink(id: string): AiraLegalDocumentLink {
  const fallback = AIRA_LEGAL_DOCUMENT_LINKS[0];
  for (let index = 0; index < AIRA_LEGAL_DOCUMENT_LINKS.length; index += 1) {
    const item = AIRA_LEGAL_DOCUMENT_LINKS[index];
    if (item.id === id) {
      return item;
    }
  }
  return fallback;
}
