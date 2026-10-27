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
  const net = add('断网', () => {
    const goOffline = mock.network === 'online';
    mock.setOffline(goOffline);
    net.textContent = goOffline ? '联网' : '断网';
  });
  add('卡住一个', () => mock.hangRandom());
  add('都恢复', () => mock.unhangAll());
  add('去吃零食', () => mock.snackRandom());
  add('来个临时工', () => mock.addTemp());
  add('走个临时工', () => mock.removeTemp());
  parent.appendChild(panel);
}
