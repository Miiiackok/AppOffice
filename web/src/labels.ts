import type { EmployeeState } from './protocol';

export const STATE_LABELS: Record<EmployeeState, string> = {
  hung: '🚽 上厕所（卡住了）',
  offline: '🏋️ 健身（断网了）',
  launching: '🎒 刚到公司',
  focused: '⌨️ 疯狂干活',
  snacking: '🍪 茶水间吃零食',
  working: '💻 在干活',
  idle: '☕ 半摸鱼',
  resting: '🎮 休闲区（很久没用）',
  off: '😴 摸鱼（没打开）',
};

export function formatUptime(launchedAt: number | null, nowSec: number): string {
  if (launchedAt === null) return '—';
  const s = Math.max(0, Math.floor(nowSec - launchedAt));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h >= 24) return `${Math.floor(h / 24)} 天 ${h % 24} 小时`;
  if (h > 0) return `${h} 小时 ${m} 分`;
  if (m > 0) return `${m} 分钟`;
  return '刚刚';
}
