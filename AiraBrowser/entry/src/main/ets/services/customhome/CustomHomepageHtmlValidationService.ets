interface CustomHomepageHtmlValidationInput {
  html: string;
  sourceLabel?: string;
}

interface CustomHomepageBlockedPattern {
  pattern: RegExp;
  message: string;
}

const CUSTOM_HOMEPAGE_REQUIRED_TAGS: string[] = [
  '<html',
  '<head',
  '<body'
];

const CUSTOM_HOMEPAGE_BLOCKED_PATTERNS: CustomHomepageBlockedPattern[] = [
  { pattern: /<iframe\b/i, message: 'HTML 中不能包含 iframe。' },
  { pattern: /<object\b/i, message: 'HTML 中不能包含 object。' },
  { pattern: /<embed\b/i, message: 'HTML 中不能包含 embed。' },
  { pattern: /<base\b/i, message: 'HTML 中不能包含 base 标签。' },
  { pattern: /<meta[^>]+http-equiv\s*=\s*["']?refresh/i, message: 'HTML 中不能包含自动刷新跳转。' },
  { pattern: /\son[a-z]+\s*=/i, message: 'HTML 中不能包含内联事件处理属性，请使用 addEventListener。' },
  { pattern: /\b(?:href|src|action|formaction)\s*=\s*["']?\s*javascript:/i, message: 'HTML 中不能包含 javascript: 链接。' },
  { pattern: /\b(?:href|src|action|formaction)\s*=\s*["']?\s*data:text\/html/i, message: 'HTML 中不能引用 data:text/html。' },
  { pattern: /navigator\.serviceworker/i, message: 'HTML 中不能注册 Service Worker。' },
  { pattern: /serviceworker\s*\.\s*register/i, message: 'HTML 中不能注册 Service Worker。' },
  { pattern: /register\s*\(\s*["'][^"']*service-worker/i, message: 'HTML 中不能注册 Service Worker。' },
  { pattern: /\bfile:\/\//i, message: 'HTML 中不能引用 file:// 绝对路径。' },
  { pattern: /<script[^>]+src\s*=\s*["']https?:\/\//i, message: 'HTML 中不能引用远程脚本。' },
  { pattern: /\b(?:window\.)?location\s*\.\s*(?:href|assign|replace)\b/i, message: 'HTML 中不能自动改写页面地址。' },
  { pattern: /\bwindow\s*\.\s*open\s*\(/i, message: 'HTML 中不能直接打开新窗口，请使用 AiraHome.openUrl。' },
  { pattern: /\bfetch\s*\(/i, message: 'HTML 中不能直接发起网络请求。' },
  { pattern: /\bXMLHttpRequest\b/i, message: 'HTML 中不能直接发起网络请求。' },
  { pattern: /\bnavigator\s*\.\s*sendBeacon\b/i, message: 'HTML 中不能直接发起网络请求。' },
  { pattern: /\bWebSocket\s*\(/i, message: 'HTML 中不能直接发起网络请求。' },
  { pattern: /\bEventSource\s*\(/i, message: 'HTML 中不能直接发起网络请求。' }
];

export class CustomHomepageHtmlValidationService {
  validateForImport(input: CustomHomepageHtmlValidationInput): void {
    const html = input.html.trim();
    if (html.length === 0) {
      throw new Error('HTML 文件不可用。');
    }
    this.ensureTextHtml(html);
    this.ensureDocumentShape(html);
    this.ensureSafeHtmlContent(html);
  }

  validateScriptAssetForImport(script: string): void {
    const source = script.trim();
    if (source.length === 0) {
      return;
    }
    this.ensureTextHtml(source);
    this.ensureSafeScriptContent(source);
  }

  looksLikeHtml(sample: string): boolean {
    const normalized = sample.trim().toLowerCase();
    if (normalized.length === 0) {
      return false;
    }
    return normalized.includes('<!doctype html') ||
      normalized.includes('<html') ||
      normalized.includes('<head') ||
      normalized.includes('<body');
  }

  private ensureTextHtml(html: string): void {
    if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(html)) {
      throw new Error('HTML 文件包含不可见控制字符。');
    }
  }

  private ensureDocumentShape(html: string): void {
    const lower = html.toLowerCase();
    const hasDoctype = lower.includes('<!doctype html');
    for (let index = 0; index < CUSTOM_HOMEPAGE_REQUIRED_TAGS.length; index += 1) {
      if (!lower.includes(CUSTOM_HOMEPAGE_REQUIRED_TAGS[index])) {
        throw new Error('HTML 文件必须包含完整的 html/head/body 结构。');
      }
    }
    if (!hasDoctype) {
      throw new Error('HTML 文件必须声明 <!doctype html>。');
    }
  }

  private ensureSafeHtmlContent(html: string): void {
    for (let index = 0; index < CUSTOM_HOMEPAGE_BLOCKED_PATTERNS.length; index += 1) {
      const blocked = CUSTOM_HOMEPAGE_BLOCKED_PATTERNS[index];
      if (blocked.pattern.test(html)) {
        throw new Error(blocked.message);
      }
    }
  }

  private ensureSafeScriptContent(script: string): void {
    const blockedPatterns: CustomHomepageBlockedPattern[] = [
      { pattern: /navigator\.serviceworker/i, message: '主页包脚本不能注册 Service Worker。' },
      { pattern: /serviceworker\s*\.\s*register/i, message: '主页包脚本不能注册 Service Worker。' },
      { pattern: /register\s*\(\s*["'][^"']*service-worker/i, message: '主页包脚本不能注册 Service Worker。' },
      { pattern: /\bfile:\/\//i, message: '主页包脚本不能引用 file:// 绝对路径。' },
      { pattern: /\b(?:window\.)?location\s*\.\s*(?:href|assign|replace)\b/i, message: '主页包脚本不能自动改写页面地址。' },
      { pattern: /\bwindow\s*\.\s*open\s*\(/i, message: '主页包脚本不能直接打开新窗口，请使用 AiraHome.openUrl。' },
      { pattern: /\bfetch\s*\(/i, message: '主页包脚本不能直接发起网络请求。' },
      { pattern: /\bXMLHttpRequest\b/i, message: '主页包脚本不能直接发起网络请求。' },
      { pattern: /\bnavigator\s*\.\s*sendBeacon\b/i, message: '主页包脚本不能直接发起网络请求。' },
      { pattern: /\bWebSocket\s*\(/i, message: '主页包脚本不能直接发起网络请求。' },
      { pattern: /\bEventSource\s*\(/i, message: '主页包脚本不能直接发起网络请求。' }
    ];
    for (let index = 0; index < blockedPatterns.length; index += 1) {
      const blocked = blockedPatterns[index];
      if (blocked.pattern.test(script)) {
        throw new Error(blocked.message);
      }
    }
  }
}
