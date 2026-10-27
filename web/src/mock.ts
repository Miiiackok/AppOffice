import type {
  EmployeeKind, EmployeeState, EmployeeStatus, InboundMessage, NetworkState, OutboundAction, RoomInfo, RosterEmployee,
} from './protocol';
import { isClosed } from './office';

/** 根据名字和颜色画一个图标，返回 PNG base64 */
export type IconMaker = (name: string, color: string) => string;
type AppDef = readonly [id: string, name: string, color: string];

const FINDER = 'com.apple.finder';
/** 和 rooms.json 一样分房间（大办公室一排 + 三间小办公室），换成假 app */
const ROOMS: RoomInfo[] = [
  { name: '大办公室', kind: 'offices' }, { name: '生活部', kind: 'shared' },
  { name: '办公部', kind: 'shared' }, { name: 'Dock 部', kind: 'shared' },
];
const STAFF: AppDef[][] = [
  [
    ['mock.browser', '浏览器', '#2F80ED'],
    ['mock.claude', 'Claude', '#D97757'],
    ['mock.gpt', 'ChatGPT', '#10A37F'],
    ['mock.chat', '聊天', '#34C759'],
  ],
  [
    ['mock.phone', '电话', '#4CD964'],
    ['mock.calendar', '日历', '#E5534B'],
    ['mock.contacts', '通讯录', '#A2845E'],
    ['mock.notes', '备忘录', '#F2C94C'],
    ['mock.reminders', '提醒事项', '#5AC8FA'],
    ['mock.tv', '视频', '#333B45'],
    ['mock.music', '音乐', '#EB5A7A'],
    ['mock.photos', '照片', '#F2994A'],
    ['mock.facetime', '视频通话', '#27AE60'],
    ['mock.messages', '信息', '#30D158'],
    ['mock.mail', '邮件', '#4FA3E0'],
    ['mock.games', '游戏', '#9B51E0'],
  ],
  [
    ['mock.keynote', '演示', '#2F80ED'],
    ['mock.numbers', '表格', '#27AE60'],
    ['mock.pages', '文稿', '#F2A65A'],
    ['mock.store', '商店', '#0A84FF'],
    ['mock.mirror', '镜像', '#636366'],
    ['mock.siri', '助理', '#BF5AF2'],
    ['mock.settings', '设置', '#8E8E93'],
  ],
  [
    [FINDER, '访达', '#3D7BFD'],
    ['mock.launcher', '启动台', '#C7C7CC'],
    ['mock.safari', 'Safari', '#0A84FF'],
    ['mock.maps', '地图', '#6FCF97'],
  ],
];
const TEMPS: AppDef[] = [
  ['mock.video', '视频剪辑', '#E76F51'],
  ['mock.editor', '编辑器', '#2A9D8F'],
  ['mock.downloader', '下载器', '#8E7DBE'],
  ['mock.game', '小游戏', '#F4A261'],
  ['mock.player', '播放器', '#E9C46A'],
  ['mock.translate', '翻译', '#4D96FF'],
  ['mock.vpn', '加速器', '#6C757D'],
];
const INITIAL_RUNNING = [FINDER, 'mock.browser', 'mock.claude', 'mock.chat', 'mock.mail', 'mock.notes'];
/** 很久没用、一开始就在休闲区玩的 */
const INITIAL_RESTING = ['mock.phone', 'mock.contacts', 'mock.tv', 'mock.facetime', 'mock.games', 'mock.keynote', 'mock.mirror', 'mock.launcher'];
const INITIAL_TEMPS = 3;
const LAUNCH_TICKS = 2;
const WANDER_CHANCE = 0.3;

/** 浏览器里开发用：假装自己是 Swift 外壳 */
export class MockHost {
  network: NetworkState = 'online';
  private roster: RosterEmployee[] = [];
  private readonly status = new Map<string, EmployeeStatus>();
  private readonly beforeOffline = new Map<string, EmployeeState>();
  private readonly launching = new Map<string, number>();
  private readonly tempPool: AppDef[] = [...TEMPS];

  constructor(
    private readonly send: (msg: InboundMessage) => void,
    private readonly icon: IconMaker,
    private readonly now: () => number = () => Date.now() / 1000,
    private readonly random: () => number = Math.random,
  ) {
    STAFF.forEach((apps, room) => apps.forEach(([id, name, color], seat) => this.add(id, name, color, 'staff', room, seat)));
    for (let i = 0; i < INITIAL_TEMPS; i++) this.takeTemp();
    for (const id of INITIAL_RUNNING) this.setState(id, 'idle');
    for (const id of INITIAL_RESTING) this.setState(id, 'resting');
    this.setState('mock.browser', 'focused');
  }

  stateOf(id: string): EmployeeState | undefined {
    return this.status.get(id)?.state;
  }

  /** 名单上有、而且没打开 */
  private closed(id: string): boolean {
    const state = this.stateOf(id);
    return state !== undefined && isClosed(state);
  }

  rosterIDs(): string[] {
    return this.roster.map(e => e.id);
  }

  handle(action: OutboundAction): void {
    switch (action.action) {
      case 'ready':
        this.sendRoster();
        this.sendStatus();
        return;
      case 'activate':
        if (this.closed(action.id)) this.launch(action.id);
        else this.focus(action.id);
        return;
      case 'launch':
        this.launch(action.id);
        return;
      case 'quit':
        this.quit(action.id);
        return;
    }
  }

  /** 每秒调一次：启动中的 app 启动完成，偶尔有人换个状态 */
  tick(): void {
    // 断网时启动卡住，等网络恢复再继续
    for (const [id, left] of this.network === 'online' ? [...this.launching] : []) {
      if (left > 1) {
        this.launching.set(id, left - 1);
        continue;
      }
      this.launching.delete(id);
      this.focus(id);
    }
    if (this.network === 'online' && this.random() < WANDER_CHANCE) {
      const pool = [...this.status.values()].filter(s => ['idle', 'working', 'snacking'].includes(s.state));
      if (pool.length > 0) this.set(this.pickFrom(pool).id, this.pickFrom<EmployeeState>(['working', 'idle', 'idle', 'snacking']));
    }
  }

  set(id: string, state: EmployeeState): void {
    if (!this.status.has(id)) return;
    this.setState(id, state);
    this.sendStatus([id]);
  }

  setOffline(offline: boolean): void {
    if (offline === (this.network === 'offline')) return;
    this.network = offline ? 'offline' : 'online';
    const changed: string[] = [];
    if (offline) {
      for (const s of this.status.values()) {
        if (isClosed(s.state) || s.id === FINDER) continue;
        this.beforeOffline.set(s.id, s.state);
        this.setState(s.id, 'offline');
        changed.push(s.id);
      }
    } else {
      for (const [id, state] of this.beforeOffline) {
        this.setState(id, state);
        changed.push(id);
      }
      this.beforeOffline.clear();
    }
    if (changed.length > 0) this.sendStatus(changed);
  }

  hangRandom(): string | null {
    const pool = [...this.status.values()].filter(s => !isClosed(s.state) && s.state !== 'hung');
    if (pool.length === 0) return null;
    const id = this.pickFrom(pool).id;
    this.set(id, 'hung');
    return id;
  }

  unhangAll(): void {
    const ids = [...this.status.values()].filter(s => s.state === 'hung').map(s => s.id);
    for (const id of ids) this.setState(id, 'idle');
    if (ids.length > 0) this.sendStatus(ids);
  }

  snackRandom(): string | null {
    const pool = [...this.status.values()].filter(s => s.state === 'idle' || s.state === 'working');
    if (pool.length === 0) return null;
    const id = this.pickFrom(pool).id;
    this.set(id, 'snacking');
    return id;
  }

  addTemp(): string | null {
    const id = this.takeTemp();
    if (!id) return null;
    this.sendRoster();
    this.sendStatus([id]);
    return id;
  }

  removeTemp(): string | null {
    const temp = this.roster.find(e => e.kind === 'temp');
    if (!temp) return null;
    this.quit(temp.id);
    return temp.id;
  }

  private launch(id: string): void {
    if (!this.closed(id)) return;
    this.launching.set(id, LAUNCH_TICKS);
    if (this.network === 'offline') {
      this.beforeOffline.set(id, 'launching');
      this.setState(id, 'offline');
    } else {
      this.setState(id, 'launching');
    }
    this.sendStatus([id]);
  }

  private focus(id: string): void {
    if (!this.status.has(id)) return;
    const others = [...this.status.values()].filter(s => s.state === 'focused' && s.id !== id).map(s => s.id);
    for (const other of others) this.setState(other, 'idle');
    this.setState(id, 'focused');
    this.sendStatus([...others, id]);
  }

  private quit(id: string): void {
    const entry = this.roster.find(e => e.id === id);
    if (!entry || this.closed(id)) return;
    this.launching.delete(id);
    this.beforeOffline.delete(id);
    if (entry.kind === 'temp') {
      this.roster = this.roster.filter(e => e.id !== id);
      this.status.delete(id);
      const def = TEMPS.find(t => t[0] === id);
      if (def) this.tempPool.push(def);
      this.sendRoster();
      return;
    }
    this.setState(id, 'off');
    this.sendStatus([id]);
  }

  private add(id: string, name: string, color: string, kind: EmployeeKind, room: number | null, seat: number | null): void {
    this.roster.push({ id, name, kind, room, seat, color, iconPNG: this.icon(name, color) });
    this.status.set(id, { id, state: 'off', cpu: 0, memMB: 0, launchedAt: null });
  }

  private takeTemp(): string | null {
    const def = this.tempPool.shift();
    if (!def) return null;
    const [id, name, color] = def;
    this.add(id, name, color, 'temp', null, null);
    this.setState(id, 'idle');
    return id;
  }

  /** 改状态；第一次运行时记下启动时间，CPU 和内存给个像样的数 */
  private setState(id: string, state: EmployeeState): void {
    const s = this.status.get(id);
    if (!s) return;
    const running = !isClosed(state);
    s.state = state;
    s.launchedAt = running ? (s.launchedAt ?? Math.floor(this.now())) : null;
    s.cpu = state === 'focused' ? 40 + Math.round(this.random() * 50)
      : state === 'working' ? 25 + Math.round(this.random() * 20)
      : running ? Math.round(this.random() * 5) : 0;
    s.memMB = state === 'snacking' ? 2400 : running ? 150 + Math.round(this.random() * 600) : 0;
  }

  private pickFrom<T>(list: T[]): T {
    return list[Math.min(list.length - 1, Math.floor(this.random() * list.length))];
  }

  private sendRoster(): void {
    this.send({ type: 'roster', rooms: ROOMS, employees: this.roster.map(e => ({ ...e })) });
  }

  private sendStatus(ids: string[] = [...this.status.keys()]): void {
    const employees = ids.filter(id => this.status.has(id)).map(id => ({ ...this.status.get(id)! }));
    this.send({ type: 'status', network: this.network, employees });
  }
}
