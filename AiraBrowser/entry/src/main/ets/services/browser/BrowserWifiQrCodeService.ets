export interface BrowserWifiQrCredentials {
  networkName: string;
  password: string;
}

export class BrowserWifiQrCodeService {
  isWifiPayload(value: string): boolean {
    return value.trim().startsWith('WIFI:');
  }

  parsePayload(value: string): BrowserWifiQrCredentials {
    const normalized = value.trim();
    if (!this.isWifiPayload(normalized)) {
      throw new Error('不是有效的 Wi-Fi 二维码。');
    }

    const fields = this.splitFields(normalized.substring('WIFI:'.length));
    let networkName = '';
    let password = '';

    fields.forEach((field: string) => {
      const separatorIndex = this.findUnescapedSeparator(field, ':');
      if (separatorIndex <= 0) {
        return;
      }
      const key = field.substring(0, separatorIndex).trim().toUpperCase();
      const fieldValue = this.unescapeValue(field.substring(separatorIndex + 1));
      if (key === 'S') {
        networkName = fieldValue;
      } else if (key === 'P') {
        password = fieldValue;
      }
    });

    if (networkName.length <= 0) {
      throw new Error('Wi-Fi 二维码未包含网络名称。');
    }
    return {
      networkName,
      password
    };
  }

  private splitFields(value: string): string[] {
    const fields: string[] = [];
    let current = '';
    let index = 0;
    while (index < value.length) {
      const character = value.charAt(index);
      if (character === '\\' && index + 1 < value.length) {
        current += character;
        index += 1;
        current += value.charAt(index);
      } else if (character === ';') {
        fields.push(current);
        current = '';
      } else {
        current += character;
      }
      index += 1;
    }
    if (current.length > 0) {
      fields.push(current);
    }
    return fields;
  }

  private findUnescapedSeparator(value: string, separator: string): number {
    let index = 0;
    while (index < value.length) {
      const character = value.charAt(index);
      if (character === '\\' && index + 1 < value.length) {
        index += 2;
        continue;
      }
      if (character === separator) {
        return index;
      }
      index += 1;
    }
    return -1;
  }

  private unescapeValue(value: string): string {
    let result = '';
    let index = 0;
    while (index < value.length) {
      const character = value.charAt(index);
      if (character === '\\' && index + 1 < value.length) {
        index += 1;
        result += value.charAt(index);
      } else {
        result += character;
      }
      index += 1;
    }
    return result;
  }
}
