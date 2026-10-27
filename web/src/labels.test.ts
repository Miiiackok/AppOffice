import { afterEach, describe, expect, it } from 'vitest';
import { setLang, systemLang } from './i18n';
import { formatUptime, stateLabel } from './labels';
import type { EmployeeState } from './protocol';

const STATES: EmployeeState[] = ['hung', 'offline', 'launching', 'focused', 'snacking', 'working', 'idle', 'resting', 'off'];

describe('labels', () => {
  afterEach(() => setLang('zh'));

  it('has a label for every state in both languages', () => {
    const zh = STATES.map(stateLabel);
    setLang('en');
    const en = STATES.map(stateLabel);
    expect(new Set(zh).size).toBe(STATES.length);
    expect(new Set(en).size).toBe(STATES.length);
    expect(en[0]).toBe('🚽 In the restroom (frozen)');
  });

  it('formats uptime', () => {
    expect(formatUptime(null, 1000)).toBe('—');
    expect(formatUptime(1000, 1030)).toBe('刚刚');
    expect(formatUptime(1000, 1000 + 125)).toBe('2 分钟');
    expect(formatUptime(0, 3 * 3600 + 12 * 60)).toBe('3 小时 12 分');
    expect(formatUptime(0, 26 * 3600)).toBe('1 天 2 小时');
    expect(formatUptime(2000, 1000)).toBe('刚刚');
    setLang('en');
    expect(formatUptime(1000, 1030)).toBe('just now');
    expect(formatUptime(0, 3 * 3600 + 12 * 60)).toBe('3 h 12 min');
  });

  it('follows the first preferred language', () => {
    expect(systemLang(['zh-Hans-CN', 'en'])).toBe('zh');
    expect(systemLang(['en-US', 'zh-Hans'])).toBe('en');
    expect(systemLang(['ja-JP'])).toBe('en');
    expect(systemLang([])).toBe('en');
  });
});
