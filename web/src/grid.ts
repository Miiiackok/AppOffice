import type { Cell } from './layout';

export interface GridLike {
  cols: number;
  rows: number;
  /** cols × rows，1 = 能走 */
  walkable: Uint8Array;
}

export function isWalkable(g: GridLike, x: number, z: number): boolean {
  return x >= 0 && z >= 0 && x < g.cols && z < g.rows && g.walkable[z * g.cols + x] === 1;
}

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]] as const;

/** 8 方向 A*；返回从起点到终点（都包含）的格子，走不到返回 null */
export function findPath(g: GridLike, from: Cell, to: Cell): Cell[] | null {
  if (!isWalkable(g, to.x, to.z)) return null;
  // 起点不在格子里（或不是整数格）就没法算
  if (!Number.isInteger(from.x) || !Number.isInteger(from.z)
    || from.x < 0 || from.z < 0 || from.x >= g.cols || from.z >= g.rows) return null;
  if (from.x === to.x && from.z === to.z) return [{ x: from.x, z: from.z }];
  const n = g.cols * g.rows;
  const cost = new Float64Array(n).fill(Infinity);
  const came = new Int32Array(n).fill(-1);
  const closed = new Uint8Array(n);
  const start = from.z * g.cols + from.x;
  const goal = to.z * g.cols + to.x;
  const heuristic = (x: number, z: number) => {
    const dx = Math.abs(x - to.x), dz = Math.abs(z - to.z);
    return dx + dz + (Math.SQRT2 - 2) * Math.min(dx, dz);
  };
  const open = new MinHeap();
  cost[start] = 0;
  open.push(start, heuristic(from.x, from.z));
  while (open.size > 0) {
    const cur = open.pop();
    if (cur === goal) break;
    if (closed[cur]) continue;
    closed[cur] = 1;
    const cx = cur % g.cols, cz = (cur - cx) / g.cols;
    for (const [dx, dz] of DIRS) {
      const nx = cx + dx, nz = cz + dz;
      if (!isWalkable(g, nx, nz)) continue;
      const diagonal = dx !== 0 && dz !== 0;
      if (diagonal && (!isWalkable(g, cx + dx, cz) || !isWalkable(g, cx, cz + dz))) continue;
      const next = nz * g.cols + nx;
      if (closed[next]) continue;
      const c = cost[cur] + (diagonal ? Math.SQRT2 : 1);
      if (c < cost[next]) {
        cost[next] = c;
        came[next] = cur;
        open.push(next, c + heuristic(nx, nz));
      }
    }
  }
  if (came[goal] === -1) return null;
  const path: Cell[] = [];
  for (let i = goal; i !== -1; i = came[i]) path.push({ x: i % g.cols, z: Math.floor(i / g.cols) });
  return path.reverse();
}

/** 按优先级取最小的二叉堆 */
class MinHeap {
  private items: number[] = [];
  private keys: number[] = [];

  get size(): number { return this.items.length; }

  push(item: number, key: number): void {
    this.items.push(item);
    this.keys.push(key);
    let i = this.items.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (this.keys[p] <= this.keys[i]) break;
      this.swap(i, p);
      i = p;
    }
  }

  pop(): number {
    const top = this.items[0];
    const lastItem = this.items.pop()!, lastKey = this.keys.pop()!;
    if (this.items.length > 0) {
      this.items[0] = lastItem;
      this.keys[0] = lastKey;
      let i = 0;
      for (;;) {
        const l = i * 2 + 1, r = l + 1;
        let m = i;
        if (l < this.keys.length && this.keys[l] < this.keys[m]) m = l;
        if (r < this.keys.length && this.keys[r] < this.keys[m]) m = r;
        if (m === i) break;
        this.swap(i, m);
        i = m;
      }
    }
    return top;
  }

  private swap(a: number, b: number): void {
    [this.items[a], this.items[b]] = [this.items[b], this.items[a]];
    [this.keys[a], this.keys[b]] = [this.keys[b], this.keys[a]];
  }
}
