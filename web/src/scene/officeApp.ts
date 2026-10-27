import * as THREE from 'three';
import { CELL } from '../layout';
import { isClosed, OfficeModel } from '../office';
import type { InboundMessage, RosterEmployee } from '../protocol';
import { Agent } from './agent';
import { buildOffice, type OfficeStatic } from './builders';
import { iconTexture, setIconAnisotropy } from './icons';
import { createStage, type Stage } from './stage';

/** 休闲区每隔这么多秒有一个人换个地方玩 */
const WANDER_SECONDS = 4;

/** 消息 → 模型 → 场景 */
export class OfficeApp {
  readonly stage: Stage;
  readonly model = new OfficeModel();
  paused = false;
  private readonly agents = new Map<string, Agent>();
  private leaving: Agent[] = [];
  private office: OfficeStatic | null = null;
  private readonly icons = new Map<string, { png: string; tex: THREE.Texture }>();
  private seed = 0;
  private nextWander = 0;

  constructor(container: HTMLElement) {
    this.stage = createStage(container);
    setIconAnisotropy(this.stage.renderer.capabilities.getMaxAnisotropy());
  }

  get rig() { return this.stage.rig; }
  get renderer() { return this.stage.renderer; }

  handle(msg: InboundMessage): void {
    switch (msg.type) {
      case 'roster':
        this.applyRoster(msg.employees);
        return;
      case 'status':
        this.model.applyStatus(msg.network, msg.employees);
        this.refreshDecor();
        this.retarget();
        return;
      case 'paused':
        this.paused = msg.paused;
        return;
    }
  }

  frame(dt: number, t: number): void {
    if (t >= this.nextWander) {
      this.nextWander = t + WANDER_SECONDS;
      if (this.model.wander()) this.retarget();
    }
    for (const a of this.agents.values()) a.update(dt, t);
    for (const a of this.leaving) a.update(dt, t);
    if (this.leaving.some(a => a.done)) {
      const done = this.leaving.filter(a => a.done);
      this.leaving = this.leaving.filter(a => !a.done);
      for (const a of done) this.disposeAgent(a);
    }
    this.stage.render();
  }

  agentRoots(): THREE.Object3D[] {
    return [...this.agents.values()].map(a => a.character.root);
  }

  seatHitBoxes(): THREE.Object3D[] {
    return this.office?.seatHitBoxes ?? [];
  }

  /** 拖着走：小人离地一点跟着鼠标 */
  dragAgent(id: string, point: THREE.Vector3): void {
    const a = this.agents.get(id);
    if (!a) return;
    a.dragging = true;
    a.character.root.position.set(point.x, 0.35, point.z);
  }

  /** 放下；返回是不是放在大门附近 */
  dropAgent(id: string, doorRadius: number): boolean {
    const a = this.agents.get(id);
    if (!a) return false;
    a.dragging = false;
    const pos = a.character.root.position;
    pos.y = 0;
    const door = this.model.layout.door;
    const near = Math.hypot(pos.x - (door.x + 0.5) * CELL, pos.z - (door.z + 0.5) * CELL) < doorRadius;
    a.replan(this.model.layout);
    return near;
  }

  private applyRoster(list: RosterEmployee[]): void {
    const { removed, layoutChanged } = this.model.applyRoster(list);
    for (const e of list) this.ensureIcon(e);
    if (layoutChanged || !this.office) this.rebuildOffice();
    const L = this.model.layout;
    if (layoutChanged) {
      // 旧格子上算的路作废；正在离开的改去新大门
      for (const a of this.agents.values()) a.replan(L);
      for (const a of this.leaving) a.leave(L.door, L);
    }
    for (const id of removed) {
      const a = this.agents.get(id);
      if (!a) continue;
      this.agents.delete(id);
      a.leave(L.door, L);
      this.leaving.push(a);
    }
    for (const e of list) {
      const tex = this.icons.get(e.id)!.tex;
      const existing = this.agents.get(e.id);
      if (existing) {
        existing.character.setShirt(e.color);
        existing.character.setIcon(tex);
        continue;
      }
      // 正式员工直接坐在工位上，临时工从大门走进来
      const emp = this.model.get(e.id)!;
      const start = e.kind === 'staff' ? this.model.deskOf(emp)?.seat ?? L.door : L.door;
      const a = new Agent(e.id, e.color, tex, start, this.seed++);
      this.agents.set(e.id, a);
      this.stage.scene.add(a.character.root);
    }
    this.refreshDecor();
    this.retarget();
  }

  private ensureIcon(e: RosterEmployee): void {
    const cur = this.icons.get(e.id);
    if (cur && cur.png === e.iconPNG) return;
    this.icons.set(e.id, { png: e.iconPNG, tex: iconTexture(e.iconPNG) });
    // 旧贴图要是还有正在离开的人戴着，等他走了再释放
    if (cur) this.releaseIcon(cur.tex);
  }

  /** 离开的人走到门口：移出场景，释放材质，图标没人用了也一起释放 */
  private disposeAgent(a: Agent): void {
    this.stage.scene.remove(a.character.root);
    const tex = a.character.icon;
    a.character.dispose();
    const entry = this.icons.get(a.id);
    if (entry && !this.agents.has(a.id) && !this.leaving.some(o => o.id === a.id)) {
      this.icons.delete(a.id);
      this.releaseIcon(entry.tex);
    }
    if (tex && tex !== entry?.tex) this.releaseIcon(tex);
  }

  /** 当前图标表和正在离开的人都不用这张贴图了才释放 */
  private releaseIcon(tex: THREE.Texture): void {
    for (const e of this.icons.values()) if (e.tex === tex) return;
    if (this.leaving.some(a => a.character.icon === tex)) return;
    tex.dispose();
  }

  private rebuildOffice(): void {
    if (this.office) {
      this.stage.scene.remove(this.office.group);
      this.office.dispose();
    }
    this.office = buildOffice(this.model.layout);
    this.stage.scene.add(this.office.group);
    this.stage.frame(this.office.bounds);
  }

  private refreshDecor(): void {
    if (!this.office) return;
    this.office.decor.forEach((d, key) => {
      const id = this.model.ownerOf(key);
      const e = id ? this.model.get(id) : undefined;
      d.setOwner(e?.info.color ?? null, e ? this.icons.get(e.info.id)?.tex ?? null : null);
      d.setScreen(!!e && !isClosed(e.status.state));
    });
  }

  private retarget(): void {
    const L = this.model.layout;
    for (const id of this.model.ids()) {
      const target = this.model.target(id);
      if (target) this.agents.get(id)?.setTarget(target, L);
    }
  }
}
