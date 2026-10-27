import { t } from './i18n';
import { formatUptime, stateLabel } from './labels';
import { isClosed, type OfficeModel } from './office';

/** 小人的名片：鼠标移上去弹出、移开收起；单击会钉住，点空白处才收。每秒刷新一次 */
export class NameCard {
  private readonly el = document.createElement('div');
  private id: string | null = null;
  /** 单击打开的，鼠标移开也不收 */
  private pinned = false;

  constructor(private readonly parent: HTMLElement, private readonly model: OfficeModel) {
    this.el.className = 'card';
    this.el.hidden = true;
    parent.appendChild(this.el);
    setInterval(() => this.render(), 1000);
  }

  /** 鼠标停在小人上；已经钉住别人的名片时不抢 */
  hover(id: string | null, clientX: number, clientY: number): void {
    if (this.pinned) return;
    if (id) this.show(id, clientX, clientY, false);
    else this.hide();
  }

  show(id: string, clientX: number, clientY: number, pin = true): void {
    this.pinned = pin;
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
    this.pinned = false;
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
      row('card-head', icon(info.iconPNG), text('strong', info.name), text('span', info.kind === 'staff' ? t('正式员工', 'Staff') : t('临时工', 'Temp'), 'card-kind')),
      text('div', stateLabel(status.state), 'card-state'),
      text('div', t(`CPU ${status.cpu}%　内存 ${status.memMB} MB`, `CPU ${status.cpu}% · Memory ${status.memMB} MB`)),
      text('div', t('已运行 ', 'Up ') + formatUptime(status.launchedAt, Date.now() / 1000)),
      text('div', isClosed(status.state) ? t('双击叫他上班', 'Double-click to launch')
        : t('双击切过去 · 拖到门口下班', 'Double-click to switch · drag to the door to quit'), 'card-hint'),
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
