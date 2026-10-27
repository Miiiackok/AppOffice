import { describe, expect, it } from 'vitest';
import {
  CELL, computeLayout, CORRIDOR_ROWS, EMPTY_SPEC, FACILITY_COLS, MIN_COLS, MIN_LEISURE_COLS, NORTH, OFFICE_D, OFFICE_W,
  ROOMS_TOP, ROW_LIMIT, SHARED_D, SOUTH, sameSpec, spotsOf, type Cell, type Layout, type LayoutSpec, type Rect,
} from './layout';

const walk = (L: Layout, c: Cell) => L.walkable[c.z * L.cols + c.x] === 1;
const FULL: LayoutSpec = {
  offices: 4,
  rooms: [{ name: '生活部', desks: 12 }, { name: '办公部', desks: 7 }, { name: 'Dock 部', desks: 4 }],
  temp: 3,
};
const withDock = (n: number): LayoutSpec => ({ ...FULL, rooms: [...FULL.rooms.slice(0, 2), { name: 'Dock 部', desks: n }] });
const SHARED_TOP = ROOMS_TOP + OFFICE_D + CORRIDOR_ROWS;
const CUBICLE_TOP = SHARED_TOP + SHARED_D + CORRIDOR_ROWS;
const inside = (r: Rect, c: Cell) => c.x > r.x && c.x < r.x + r.w - 1 && c.z > r.z && c.z < r.z + r.d - 1;
const overlaps = (a: Rect, b: Rect) => a.x < b.x + b.w && b.x < a.x + a.w && a.z < b.z + b.d && b.z < a.z + a.d;

describe('computeLayout', () => {
  it('stacks facilities, private offices, shared rooms and temp cubicles top to bottom', () => {
    const L = computeLayout(FULL);
    expect(L.cols).toBe(63);
    expect(L.cubicleTop).toBe(CUBICLE_TOP);
    expect(L.rows).toBe(CUBICLE_TOP + 9 + 3);
    expect(L.offices).toHaveLength(4);
    for (const o of L.offices) expect(o.rect).toMatchObject({ z: ROOMS_TOP, w: OFFICE_W, d: OFFICE_D });
    for (const r of L.rooms) expect(r.rect).toMatchObject({ z: SHARED_TOP, d: SHARED_D });
    expect(L.rooms.map(r => [r.name, r.desks.length])).toEqual([['生活部', 12], ['办公部', 7], ['Dock 部', 4]]);
    expect(L.cubicles).toHaveLength(3);
    expect(L.cubicles[0].rect.z).toBe(CUBICLE_TOP);
    expect(L.walkable).toHaveLength(L.cols * L.rows);
  });

  it('gives each private office one desk inside its glass walls', () => {
    const L = computeLayout(FULL);
    for (const o of L.offices) {
      expect(o.desks).toHaveLength(1);
      expect(inside(o.rect, o.desks[0].seat)).toBe(true);
      expect(o.desks[0].seat.facing).toBe(NORTH);
      expect(walk(L, { x: o.rect.x, z: o.rect.z + 2 })).toBe(false);
      expect(walk(L, { x: o.door.x, z: o.rect.z + o.rect.d - 1 })).toBe(true);
      expect(walk(L, { x: o.door.x - 1, z: o.rect.z + o.rect.d - 1 })).toBe(false);
    }
    for (let i = 1; i < L.offices.length; i++) expect(overlaps(L.offices[i - 1].rect, L.offices[i].rect)).toBe(false);
  });

  it('lays shared rooms out in two rows of plain desks, side by side', () => {
    const L = computeLayout(FULL);
    expect(L.rooms.map(r => r.rect.w)).toEqual([3 + 6 * 4, 3 + 4 * 4, 3 + 2 * 4]);
    expect(L.rooms[1].rect.x).toBe(L.rooms[0].rect.x + L.rooms[0].rect.w + 1);
    for (const room of L.rooms) {
      for (const d of room.desks) {
        expect(inside(room.rect, d.seat)).toBe(true);
        expect(walk(L, d.desk)).toBe(false);
        expect(d.seat).toEqual({ x: d.desk.x + 1, z: d.desk.z + 2, facing: NORTH });
      }
    }
    // 7 个人：第一排 4 个，第二排 3 个
    const z = L.rooms[1].desks.map(d => d.seat.z);
    expect(new Set(z.slice(0, 4)).size).toBe(1);
    expect(z[4]).toBeGreaterThan(z[0]);
  });

  it('wraps rooms onto new rows instead of growing past the row limit', () => {
    const L = computeLayout({ offices: 6, rooms: [...FULL.rooms, { name: '游戏部', desks: 8 }], temp: 0 });
    // 4 间大办公室正好一排，多出来的 2 间换到第二排
    expect(L.offices.map(o => o.rect.z)).toEqual([ROOMS_TOP, ROOMS_TOP, ROOMS_TOP, ROOMS_TOP,
      ROOMS_TOP + OFFICE_D + CORRIDOR_ROWS, ROOMS_TOP + OFFICE_D + CORRIDOR_ROWS]);
    const sharedTop = ROOMS_TOP + 2 * (OFFICE_D + CORRIDOR_ROWS);
    expect(L.rooms.map(r => r.rect.z)).toEqual([sharedTop, sharedTop, sharedTop, sharedTop + SHARED_D + CORRIDOR_ROWS]);
    expect(L.cols).toBe(2 * 2 + ROW_LIMIT);
    expect(L.cubicleTop).toBe(sharedTop + 2 * (SHARED_D + CORRIDOR_ROWS));
    const all = [...L.offices, ...L.rooms].map(r => r.rect);
    for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) expect(overlaps(all[i], all[j])).toBe(false);
  });

  it('a room wider than the limit gets a row of its own and widens the office', () => {
    const L = computeLayout({ offices: 0, rooms: [{ name: 'A', desks: 2 }, { name: '大', desks: 40 }], temp: 0 });
    expect(L.rooms[1].rect.w).toBe(3 + 20 * 4);
    expect(L.rooms[1].rect.z).toBeGreaterThan(L.rooms[0].rect.z);
    expect(L.cols).toBe(2 * 2 + 3 + 20 * 4);
  });

  it('skips empty rooms and is never narrower than the facility band', () => {
    const L = computeLayout(EMPTY_SPEC);
    expect(L.cols).toBeGreaterThanOrEqual(MIN_COLS);
    expect(L.offices).toHaveLength(0);
    expect(L.cubicleTop).toBe(ROOMS_TOP);
    const some = computeLayout({ offices: 0, rooms: [{ name: 'A', desks: 0 }, { name: 'B', desks: 3 }], temp: 0 });
    expect(some.rooms[0].desks).toHaveLength(0);
    expect(some.rooms[1].desks).toHaveLength(3);
    expect(some.cubicleTop).toBe(ROOMS_TOP + SHARED_D + CORRIDOR_ROWS);
  });

  it('builds exactly one cubicle per temp and adds rows as needed', () => {
    const L = computeLayout({ ...FULL, temp: 0 });
    expect(L.cubicleRows).toBe(1);
    const many = computeLayout({ ...FULL, temp: L.perRow + 1 });
    expect(many.cubicles).toHaveLength(L.perRow + 1);
    expect(many.cubicleRows).toBe(2);
    expect(many.rows).toBe(L.rows + 9);
    expect(many.cubicles[L.perRow].rect.z).toBe(CUBICLE_TOP + 9);
  });

  it('places cubicle seats in front of desks and closes the last one', () => {
    const L = computeLayout(FULL);
    const c = L.cubicles[2];
    expect(c.seat).toEqual({ x: c.rect.x + 3, z: c.rect.z + 3, facing: NORTH });
    expect(walk(L, { x: c.desk.x, z: c.desk.z })).toBe(false);
    expect(walk(L, { x: c.rect.x + 6, z: c.rect.z + 1 })).toBe(false);
    expect(walk(L, { x: c.rect.x + 7, z: c.rect.z + 1 })).toBe(true);
  });

  it('keeps every spot walkable', () => {
    const specs = [EMPTY_SPEC, FULL, { ...FULL, temp: 25 }, { offices: 7, rooms: [...FULL.rooms, ...FULL.rooms], temp: 1 }];
    for (const spec of specs) {
      const L = computeLayout(spec);
      for (const s of spotsOf(L)) expect(walk(L, s), `${JSON.stringify(spec)} ${JSON.stringify(s)}`).toBe(true);
    }
  });

  it('puts the door on the bottom edge near the right', () => {
    const L = computeLayout(FULL);
    expect(L.door).toEqual({ x: L.cols - 4, z: L.rows - 1, facing: SOUTH });
  });

  it('has the facility capacity from the design', () => {
    const L = computeLayout(FULL);
    expect(L.toilets).toHaveLength(2);
    expect(L.treadmills).toHaveLength(3);
    expect(L.pantry).toHaveLength(4);
  });

  it('keeps facilities at fixed widths and gives the rest of the band to the leisure area', () => {
    for (const spec of [EMPTY_SPEC, FULL, withDock(20)]) {
      const L = computeLayout(spec);
      const { toilet, gym, pantry, leisure } = L.zones;
      expect([toilet.x, gym.x, pantry.x, leisure.x]).toEqual([0, 9, 19, FACILITY_COLS]);
      expect(leisure.x + leisure.w).toBe(L.cols);
      expect(leisure.w).toBeGreaterThanOrEqual(MIN_LEISURE_COLS);
      expect(L.fridge.x + L.fridge.w).toBeLessThanOrEqual(pantry.x + pantry.w);
      for (const t of L.treadmills) {
        expect(t.x).toBeGreaterThanOrEqual(gym.x);
        expect(t.x).toBeLessThan(gym.x + gym.w);
      }
      for (const s of L.leisure.spots) {
        expect(s.x).toBeGreaterThanOrEqual(leisure.x);
        expect(s.x).toBeLessThan(leisure.x + leisure.w);
        expect(s.z).toBeLessThan(leisure.d);
      }
      const { tv } = L.leisure;
      expect(tv.x).toBeGreaterThanOrEqual(leisure.x);
      expect(tv.x + tv.w).toBeLessThanOrEqual(leisure.x + leisure.w);
    }
  });

  it('has arcades, watchers and bean bags in the leisure area', () => {
    const L = computeLayout(FULL);
    const count = (k: string) => L.leisure.spots.filter(s => s.kind === k).length;
    expect(L.leisure.arcades).toHaveLength(4);
    expect(count('arcade')).toBe(4);
    expect(count('watch')).toBe(3);
    expect(count('beanbag')).toBe(12);
    // 每台游戏机前面站一个人
    for (const a of L.leisure.arcades) expect(L.leisure.spots).toContainEqual({ x: a.x, z: 2, facing: NORTH, kind: 'arcade' });
    // 最窄时也有地方
    expect(computeLayout(EMPTY_SPEC).leisure.spots.length).toBeGreaterThanOrEqual(10);
    const spots = L.leisure.spots.map(s => `${s.x},${s.z}`);
    expect(new Set(spots).size).toBe(spots.length);
  });

  it('compares specs', () => {
    expect(sameSpec(FULL, { ...FULL, rooms: FULL.rooms.map(r => ({ ...r })) })).toBe(true);
    expect(sameSpec(FULL, { ...FULL, temp: 4 })).toBe(false);
    expect(sameSpec(FULL, withDock(5))).toBe(false);
    expect(sameSpec(FULL, { ...FULL, rooms: [{ name: '改名了', desks: 12 }, ...FULL.rooms.slice(1)] })).toBe(false);
    expect(computeLayout(FULL).spec).toEqual(FULL);
  });

  it('uses half-metre cells', () => {
    expect(CELL).toBe(0.5);
  });
});
