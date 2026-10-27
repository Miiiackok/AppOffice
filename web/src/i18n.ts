/** 界面语言：Swift 外壳发 locale 消息来定；mock 模式看 ?lang= 或浏览器语言 */
export type Lang = 'zh' | 'en';

let current: Lang = 'zh';

export function getLang(): Lang {
  return current;
}

export function setLang(lang: Lang): void {
  current = lang;
  if (typeof document !== 'undefined') document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
}

/** 首选语言是中文就中文，其他都英文（和 Swift 的 Lang.system 一样） */
export function systemLang(languages: readonly string[]): Lang {
  return languages[0]?.toLowerCase().startsWith('zh') ? 'zh' : 'en';
}

/** 按当前语言二选一 */
export function t(zh: string, en: string): string {
  return current === 'en' ? en : zh;
}
