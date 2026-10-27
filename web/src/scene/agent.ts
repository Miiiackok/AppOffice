import * as THREE from 'three';
import { findPath, type GridLike } from '../grid';
import { CELL, type Cell, type Spot } from '../layout';
import type { Target } from '../office';
import { Character } from './character';

/** 走路速度，米/秒 */
const SPEED = 1.6;
const SLACK_VARIANTS = 4;

const toWorld = (c: Cell) => new THREE.Vector3((c.x + 0.5) * CELL, 0, (c.z + 0.5) * CELL);

/** 一个员工：负责走路、换动作；去哪儿由 OfficeModel 决定 */
export class Agent {
  readonly character: Character;
  leaving = false;
  done = false;
  dragging = false;
  private path: THREE.Vector3[] = [];
  private target: Target | null = null;
  private targetKey = '';
  private slackVariant: number;
  private nextSlackSwitch = 0;
  /** 每个人的动画时间错开一点 */
  private readonly phase: number;

  constructor(readonly id: string, color: string, icon: THREE.Texture | null, start: Spot, seed: number) {
    this.character = new Character(color, icon);
    this.character.root.userData.agentId = id;
    this.character.root.position.copy(toWorld(start));
    this.character.root.rotation.y = start.facing;
    this.slackVariant = seed % SLACK_VARIANTS;
    this.phase = seed * 1.37;
  }

  /** 目标格子变了才重新寻路；force 用于放下后重新规划 */
  setTarget(target: Target, grid: GridLike, force = false): void {
    this.target = target;
    const key = `${target.spot.x},${target.spot.z}`;
    if (!force && key === this.targetKey) return;
    this.targetKey = key;
    const pos = this.character.root.position;
    // 站在格子外面（布局缩小、被拖到墙外）就从最近的格子算起
    const from = {
      x: THREE.MathUtils.clamp(Math.floor(pos.x / CELL), 0, grid.cols - 1),
      z: THREE.MathUtils.clamp(Math.floor(pos.z / CELL), 0, grid.rows - 1),
    };
    const cells = findPath(grid, from, target.spot);
    // 走不到就直接朝目标走过去
    this.path = cells ? cells.slice(1).map(toWorld) : [];
    if (this.path.length === 0) this.path.push(toWorld(target.spot));
  }

  leave(door: Spot, grid: GridLike): void {
    this.leaving = true;
    // 正被拖着也得放手，不然会一直悬在半空
    this.dragging = false;
    this.character.root.position.y = 0;
    this.setTarget({ spot: door, activity: 'wait', intensity: 0 }, grid, true);
  }

  replan(grid: GridLike): void {
    if (this.target) this.setTarget(this.target, grid, true);
  }

  update(dt: number, time: number): void {
    const c = this.character;
    const t = time + this.phase;
    if (this.dragging) {
      c.pose('carried', t);
      return;
    }
    const pos = c.root.position;
    const next = this.path[0];
    if (next) {
      const dx = next.x - pos.x, dz = next.z - pos.z;
      const dist = Math.hypot(dx, dz), step = SPEED * dt;
      if (dist > 1e-4) c.root.rotation.y = Math.atan2(dx, dz);
      if (dist <= step) {
        pos.set(next.x, 0, next.z);
        this.path.shift();
      } else {
        pos.x += (dx / dist) * step;
        pos.z += (dz / dist) * step;
      }
      c.pose('walk', t);
      return;
    }
    if (this.leaving) {
      this.done = true;
      return;
    }
    if (!this.target) {
      c.pose('stand', t);
      return;
    }
    c.root.rotation.y = this.target.spot.facing;
    if (this.target.activity === 'slack' && time >= this.nextSlackSwitch) {
      if (this.nextSlackSwitch > 0) {
        this.slackVariant = (this.slackVariant + 1 + Math.floor(Math.random() * (SLACK_VARIANTS - 1))) % SLACK_VARIANTS;
      }
      this.nextSlackSwitch = time + 8 + Math.random() * 8;
    }
    c.pose(this.target.activity, t, this.target.intensity, this.slackVariant);
  }
}
