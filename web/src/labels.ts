import { t } from './i18n';
import type { EmployeeState } from './protocol';

export function stateLabel(state: EmployeeState): string {
  switch (state) {
    case 'hung': return t('🚽 上厕所（卡住了）', '🚽 In the restroom (frozen)');
    case 'offline': return t('🏋️ 健身（断网了）', '🏋️ At the gym (offline)');
    case 'launching': return t('🎒 刚到公司', '🎒 Just arrived (launching)');
    case 'focused': return t('⌨️ 疯狂干活', '⌨️ Typing like mad');
    case 'snacking': return t('🍪 茶水间吃零食', '🍪 Snacking in the pantry');
    case 'working': return t('💻 在干活', '💻 Working');
    case 'idle': return t('☕ 半摸鱼', '☕ Sipping coffee (idle)');
    case 'resting': return t('🎮 休闲区（很久没用）', '🎮 In the lounge (long unused)');
    case 'off': return t('😴 摸鱼（没打开）', '😴 Slacking (not running)');
  }
}

export function formatUptime(launchedAt: number | null, nowSec: number): string {
  if (launchedAt === null) return '—';
  const s = Math.max(0, Math.floor(nowSec - launchedAt));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h >= 24) return t(`${Math.floor(h / 24)} 天 ${h % 24} 小时`, `${Math.floor(h / 24)} d ${h % 24} h`);
  if (h > 0) return t(`${h} 小时 ${m} 分`, `${h} h ${m} min`);
  if (m > 0) return t(`${m} 分钟`, `${m} min`);
  return t('刚刚', 'just now');
}
