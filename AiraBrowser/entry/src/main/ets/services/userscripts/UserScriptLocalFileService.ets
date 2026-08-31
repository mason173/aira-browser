import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import buffer from '@ohos.buffer';

const MAX_LOCAL_USER_SCRIPT_CHARS: number = 5 * 1024 * 1024;

export class UserScriptLocalFileService {
  pickScriptFileUri(context: common.UIAbilityContext): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context);
    return documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.user.js', '.js', '.txt']
    }).then((uris: Array<string>) => uris.length > 0 ? uris[0] : undefined);
  }

  async readScriptFile(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const chunks: string[] = [];
    const chunkSize = 64 * 1024;
    let totalLength = 0;
    try {
      let bytesRead = 0;
      do {
        const data = new ArrayBuffer(chunkSize);
        bytesRead = await fileIo.read(file.fd, data);
        if (bytesRead > 0) {
          totalLength += bytesRead;
          if (totalLength > MAX_LOCAL_USER_SCRIPT_CHARS) {
            throw new Error('脚本超过 5 MB，暂不支持安装。');
          }
          chunks.push(buffer.from(data, 0, bytesRead).toString('utf8'));
        }
      } while (bytesRead === chunkSize);
    } finally {
      await fileIo.close(file);
    }
    return chunks.join('').trim();
  }
}
