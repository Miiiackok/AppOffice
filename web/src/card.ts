import { formatUptime, STATE_LABELS } from './labels';
import { isClosed, type OfficeModel } from './office';

/** 点小人弹出的名片，每秒刷新一次 */
export class NameCard {
  private readonly el = document.createElement('div');
  private id: string | null = null;

  constructor(private readonly parent: HTMLElement, private readonly model: OfficeModel) {
    this.el.className = 'card';
    this.el.hidden = true;
    parent.appendChild(this.el);
    setInterval(() => this.render(), 1000);
  }

  show(id: string, clientX: number, clientY: number): void {
    this.id = id;
    this.render();
    this.el.hidden = false;
    const r = this.parent.getBoundingClientRect();
    const w = this.el.offsetWidth, h = this.el.offsetHeight;
    this.el.style.left = `${Math.max(8, Math.min(clientX - r.left + 12, r.width - w - 8))}px`;
    this.el.style.top = `${Math.max(8, Math.min(clientY - r.top + 12, r.height - h - 8))}px`;
  }

  hide(): void {
    this.id = null;
    this.el.hidden = true;
  }

  private render(): void {
    if (!this.id) return;
    const e = this.model.get(this.id);
    if (!e) {
      this.hide();
      return;
    }
    const { info, status } = e;
    this.el.replaceChildren(
      row('card-head', icon(info.iconPNG), text('strong', info.name), text('span', info.kind === 'staff' ? '正式员工' : '临时工', 'card-kind')),
      text('div', STATE_LABELS[status.state], 'card-state'),
      text('div', `CPU ${status.cpu}%　内存 ${status.memMB} MB`),
      text('div', `已运行 ${formatUptime(status.launchedAt, Date.now() / 1000)}`),
      text('div', isClosed(status.state) ? '双击叫他上班' : '双击切过去 · 拖到门口下班', 'card-hint'),
    );
  }
}

function text(tag: string, content: string, className = ''): HTMLElement {
  const n = document.createElement(tag);
  n.textContent = content;
  if (className) n.className = className;
  return n;
}

function icon(png: string): HTMLImageElement {
  const img = document.createElement('img');
  img.src = `data:image/png;base64,${png}`;
  img.width = img.height = 24;
  return img;
}

function row(className: string, ...children: HTMLElement[]): HTMLElement {
  const d = document.createElement('div');
  d.className = className;
  d.append(...children);
  return d;
}
