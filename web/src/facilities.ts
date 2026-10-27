export type Place = { kind: 'seat'; index: number } | { kind: 'queue'; index: number };

/** 有固定座位的设施（厕所坑位、跑步机、吧台、开放工位），坐满了排队 */
export class Facility {
  private readonly slots: (string | null)[];
  private readonly queue: string[] = [];

  constructor(seats: number) {
    this.slots = Array.from({ length: seats }, () => null);
  }

  join(id: string): void {
    if (this.placeOf(id)) return;
    const free = this.slots.indexOf(null);
    if (free >= 0) this.slots[free] = id;
    else this.queue.push(id);
  }

  /** 离开；坐着的人走了，队首补进他的座位 */
  leave(id: string): void {
    const i = this.slots.indexOf(id);
    if (i >= 0) {
      this.slots[i] = this.queue.shift() ?? null;
      return;
    }
    const q = this.queue.indexOf(id);
    if (q >= 0) this.queue.splice(q, 1);
  }

  placeOf(id: string): Place | null {
    const i = this.slots.indexOf(id);
    if (i >= 0) return { kind: 'seat', index: i };
    const q = this.queue.indexOf(id);
    return q >= 0 ? { kind: 'queue', index: q } : null;
  }

  members(): string[] {
    return [...this.slots.filter((s): s is string => s !== null), ...this.queue];
  }
}

/** 休闲区：不排队，每人随便占一个空位，时不时有人换个地方玩 */
export class Roaming {
  private readonly at = new Map<string, number>();

  constructor(private capacity: number, private readonly random: () => number) {}

  /** 布局变了：位置不够的人重新找地方 */
  resize(capacity: number): void {
    this.capacity = capacity;
    const out = [...this.at].filter(([, i]) => i >= capacity).map(([id]) => id);
    for (const id of out) this.at.delete(id);
    for (const id of out) this.join(id);
  }

  join(id: string): void {
    if (this.at.has(id)) return;
    const free = this.free();
    // 坐满了就挤在最后一个位置上
    this.at.set(id, free.length > 0 ? free[Math.floor(this.random() * free.length)] : this.capacity);
  }

  leave(id: string): void {
    this.at.delete(id);
  }

  placeOf(id: string): number | undefined {
    return this.at.get(id);
  }

  /** 随便挑一个人换到另一个空位；没人或没空位就不动，返回换了谁 */
  wander(): string | null {
    const free = this.free();
    if (this.at.size === 0 || free.length === 0) return null;
    const ids = [...this.at.keys()];
    const id = ids[Math.floor(this.random() * ids.length)];
    this.at.set(id, free[Math.floor(this.random() * free.length)]);
    return id;
  }

  private free(): number[] {
    const taken = new Set(this.at.values());
    return Array.from({ length: this.capacity }, (_, i) => i).filter(i => !taken.has(i));
  }
}
