import { Facility, Roaming, type Place } from './facilities';
import { computeLayout, NO_COUNTS, sameCounts, type Desk, type Layout, type LeisureKind, type RoomCounts, type Spot } from './layout';
import type { EmployeeState, EmployeeStatus, NetworkState, RosterEmployee } from './protocol';

export type Activity = 'slack' | 'idle' | 'type' | 'boot' | 'toilet' | 'wait' | 'run' | 'pushup' | 'eat' | 'sofa'
  | 'arcade' | 'lounge' | 'watch';

/** 没打开：在座位上摸鱼（off），或者很久没用、去休闲区玩（resting） */
export const isClosed = (state: EmployeeState): boolean => state === 'off' || state === 'resting';

const LEISURE_ACTIVITY: Record<LeisureKind, Activity> = { arcade: 'arcade', beanbag: 'lounge', watch: 'watch' };

/** 员工该去的格子、到了做什么、动作强度（0–1，来自 CPU） */
export interface Target {
  spot: Spot;
  activity: Activity;
  intensity: number;
}

export interface Employee {
  info: RosterEmployee;
  status: EmployeeStatus;
}

type FacilityName = 'toilet' | 'gym' | 'pantry';

/** 设计文档 2.2：卡住去厕所，断网去健身房，内存高去茶水间 */
export function facilityFor(state: EmployeeState): FacilityName | null {
  if (state === 'hung') return 'toilet';
  if (state === 'offline') return 'gym';
  if (state === 'snacking') return 'pantry';
  return null;
}

export function deskActivity(state: EmployeeState): Activity {
  switch (state) {
    case 'focused':
    case 'working':
      return 'type';
    case 'launching':
      return 'boot';
    case 'off':
      return 'slack';
    default:
      return 'idle';
  }
}

/** 工位的名字（office:0、apple:3、temp:2）：场景里的装饰和点击盒靠它找主人 */
export function deskKey(e: Employee, tempSeat: number | undefined): string | null {
  if (e.info.kind === 'temp') return tempSeat === undefined ? null : `temp:${tempSeat}`;
  return e.info.room && e.info.seat !== null ? `${e.info.room}:${e.info.seat}` : null;
}

/** 排队的人比位置多时，多出来的都站在最后一个位置 */
const pick = <T extends Spot>(spots: T[], i: number): T => spots[Math.min(i, spots.length - 1)];

export class OfficeModel {
  layout: Layout = computeLayout(NO_COUNTS);
  network: NetworkState = 'online';
  private readonly employees = new Map<string, Employee>();
  private readonly facilities: Record<FacilityName, Facility> = {
    toilet: new Facility(this.layout.toilets.length),
    gym: new Facility(this.layout.treadmills.length),
    pantry: new Facility(this.layout.pantry.length),
  };
  /** 临时工 → 隔间序号：新来的坐最小的空位，有人走了别人不挪 */
  private readonly tempSeats = new Map<string, number>();
  private readonly leisure: Roaming;

  constructor(random: () => number = Math.random) {
    this.leisure = new Roaming(this.layout.leisure.spots.length, random);
  }

  ids(): string[] {
    return [...this.employees.keys()];
  }

  get(id: string): Employee | undefined {
    return this.employees.get(id);
  }

  keyOf(id: string): string | null {
    const e = this.employees.get(id);
    return e ? deskKey(e, this.tempSeats.get(id)) : null;
  }

  ownerOf(key: string): string | null {
    for (const id of this.employees.keys()) if (this.keyOf(id) === key) return id;
    return null;
  }

  applyRoster(list: RosterEmployee[]): { added: string[]; removed: string[]; layoutChanged: boolean } {
    const incoming = new Set(list.map(e => e.id));
    const removed = this.ids().filter(id => !incoming.has(id));
    for (const id of removed) this.forget(id);
    const added: string[] = [];
    for (const info of list) {
      const existing = this.employees.get(info.id);
      // 临时工被固定到 Dock（或反过来）
      if (info.kind === 'staff') this.tempSeats.delete(info.id);
      if (existing) {
        existing.info = info;
      } else {
        const state: EmployeeState = info.kind === 'staff' ? 'off' : 'launching';
        this.employees.set(info.id, { info, status: { id: info.id, state, cpu: 0, memMB: 0, launchedAt: null } });
        added.push(info.id);
      }
      if (info.kind === 'temp' && !this.tempSeats.has(info.id)) this.tempSeats.set(info.id, this.freeTempSeat());
    }
    const counts = this.counts();
    const layoutChanged = !sameCounts(counts, this.layout.counts);
    if (layoutChanged) {
      this.layout = computeLayout(counts);
      this.leisure.resize(this.layout.leisure.spots.length);
    }
    return { added, removed, layoutChanged };
  }

  applyStatus(network: NetworkState, statuses: EmployeeStatus[]): void {
    this.network = network;
    for (const s of statuses) {
      const e = this.employees.get(s.id);
      if (!e) continue;
      e.status = s;
      const want = facilityFor(s.state);
      for (const [name, f] of Object.entries(this.facilities) as [FacilityName, Facility][]) {
        if (name === want) f.join(s.id);
        else f.leave(s.id);
      }
      if (s.state === 'resting') this.leisure.join(s.id);
      else this.leisure.leave(s.id);
    }
  }

  /** 休闲区里随便一个人换个地方玩；返回有没有人换 */
  wander(): boolean {
    return this.leisure.wander() !== null;
  }

  target(id: string): Target | null {
    const e = this.employees.get(id);
    if (!e) return null;
    const { state, cpu } = e.status;
    const intensity = Math.max(0, Math.min(1, cpu / 100));
    const facility = facilityFor(state);
    if (facility) return this.facilityTarget(facility, this.facilities[facility].placeOf(id)!, intensity);
    if (state === 'resting') {
      const spot = pick(this.layout.leisure.spots, this.leisure.placeOf(id) ?? 0);
      return { spot, activity: LEISURE_ACTIVITY[spot.kind], intensity };
    }
    const desk = this.deskOf(e);
    // 没有座位（名单和布局对不上）就在门口等着
    return desk
      ? { spot: desk.seat, activity: deskActivity(state), intensity }
      : { spot: this.layout.door, activity: 'wait', intensity };
  }

  deskOf(e: Employee): Desk | undefined {
    const L = this.layout;
    if (e.info.kind === 'temp') {
      const seat = this.tempSeats.get(e.info.id);
      return seat === undefined ? undefined : L.cubicles[seat];
    }
    const { room, seat } = e.info;
    if (!room || seat === null) return undefined;
    return room === 'office' ? L.offices[seat]?.desks[0] : L.rooms[room].desks[seat];
  }

  /** 每个房间要几个座位：按最大的座位号算，名单有空号也不会坐错 */
  private counts(): RoomCounts {
    const c: RoomCounts = { ...NO_COUNTS };
    for (const e of this.employees.values()) {
      const { room, seat } = e.info;
      if (e.info.kind === 'staff' && room && seat !== null) c[room] = Math.max(c[room], seat + 1);
    }
    for (const seat of this.tempSeats.values()) c.temp = Math.max(c.temp, seat + 1);
    return c;
  }

  private freeTempSeat(): number {
    const taken = new Set(this.tempSeats.values());
    let i = 0;
    while (taken.has(i)) i++;
    return i;
  }

  private facilityTarget(name: FacilityName, place: Place, intensity: number): Target {
    const L = this.layout;
    const seated = place.kind === 'seat';
    switch (name) {
      case 'toilet':
        return seated
          ? { spot: L.toilets[place.index], activity: 'toilet', intensity }
          : { spot: pick(L.toiletQueue, place.index), activity: 'wait', intensity };
      case 'gym':
        return seated
          ? { spot: L.treadmills[place.index], activity: 'run', intensity }
          : { spot: pick(L.gymMats, place.index), activity: 'pushup', intensity };
      case 'pantry':
        return seated
          ? { spot: L.pantry[place.index], activity: 'eat', intensity }
          : { spot: pick(L.pantryQueue, place.index), activity: 'wait', intensity };
    }
  }

  private forget(id: string): void {
    for (const f of Object.values(this.facilities)) f.leave(id);
    this.leisure.leave(id);
    this.tempSeats.delete(id);
    this.employees.delete(id);
  }
}
