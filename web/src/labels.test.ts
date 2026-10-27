import { describe, expect, it } from 'vitest';
import { formatUptime, STATE_LABELS } from './labels';

describe('labels', () => {
  it('has a label for every state', () => {
    expect(Object.keys(STATE_LABELS).sort()).toEqual(
      ['focused', 'hung', 'idle', 'launching', 'off', 'offline', 'resting', 'snacking', 'working']);
  });

  it('formats uptime', () => {
    expect(formatUptime(null, 1000)).toBe('—');
    expect(formatUptime(1000, 1030)).toBe('刚刚');
    expect(formatUptime(1000, 1000 + 125)).toBe('2 分钟');
    expect(formatUptime(0, 3 * 3600 + 12 * 60)).toBe('3 小时 12 分');
    expect(formatUptime(0, 26 * 3600)).toBe('1 天 2 小时');
    expect(formatUptime(2000, 1000)).toBe('刚刚');
  });
});
