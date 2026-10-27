import { t } from './i18n';
import type { MockHost } from './mock';

/** mock 模式左上角的调试按钮 */
export function mountMockPanel(parent: HTMLElement, mock: MockHost): void {
  const panel = document.createElement('div');
  panel.className = 'mock-panel';
  const add = (label: string, onClick: () => void) => {
    const b = document.createElement('button');
    b.textContent = label;
    b.addEventListener('click', onClick);
    panel.appendChild(b);
    return b;
  };
  const net = add(t('断网', 'Go offline'), () => {
    const goOffline = mock.network === 'online';
    mock.setOffline(goOffline);
    net.textContent = goOffline ? t('联网', 'Go online') : t('断网', 'Go offline');
  });
  add(t('卡住一个', 'Freeze one'), () => mock.hangRandom());
  add(t('都恢复', 'Unfreeze all'), () => mock.unhangAll());
  add(t('去吃零食', 'Snack'), () => mock.snackRandom());
  add(t('来个临时工', 'Add a temp'), () => mock.addTemp());
  add(t('走个临时工', 'Remove a temp'), () => mock.removeTemp());
  parent.appendChild(panel);
}
