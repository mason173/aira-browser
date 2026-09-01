export const PHONE_PAGE_PUSH_MESSAGE_TYPE = 'LEAFTAB_PHONE_PAGE_PUSH_NOW';

export type PhonePagePushRequest = {
  url: string;
  originalUrl?: string;
  desktopUrl?: string;
  title?: string;
};

export type PhonePagePushMessage = {
  type: typeof PHONE_PAGE_PUSH_MESSAGE_TYPE;
  payload?: PhonePagePushRequest;
};
