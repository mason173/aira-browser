import { pasteboard } from '@kit.BasicServicesKit';

export class UserScriptNativeClipboardService {
  async setText(text: string): Promise<void> {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await pasteboard.getSystemPasteboard().setData(data);
  }
}
