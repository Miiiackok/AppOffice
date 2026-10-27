import { describe, expect, it } from 'vitest';
import {
  CELL, computeLayout, FACILITY_COLS, FIRST_CUBICLE_Z, MIN_COLS, MIN_LEISURE_COLS, NO_COUNTS, NORTH, OFFICE_D, OFFICE_TOP, OFFICE_W, SHARED_D, SHARED_ROOMS,
  SHARED_TOP, SOUTH, sameCounts, spotsOf, type Cell, type Layout, type Rect, type RoomCounts,
} from './layout';

const walk = (L: Layout, c: Cell) => L.walkable[c.z * L.cols + c.x] === 1;
const FULL: RoomCounts = { office: 4, apple: 12, tools: 7, dock: 4, temp: 3 };
const inside = (r: Rect, c: Cell) => c.x > r.x && c.x < r.x + r.w - 1 && c.z > r.z && c.z < r.z + r.d - 1;
const overlaps = (a: Rect, b: Rect) => a.x < b.x + b.w && b.x < a.x + a.w && a.z < b.z + b.d && b.z < a.z + a.d;

describe('computeLayout', () => {
  it('stacks facilities, private offices, shared rooms and temp cubicles top to bottom', () => {
    const L = computeLayout(FULL);
    expect(L.cols).toBe(63);
    expect(L.rows).toBe(FIRST_CUBICLE_Z + 9 + 3);
    expect(L.offices).toHaveLength(4);
    for (const o of L.offices) expect(o.rect).toMatchObject({ z: OFFICE_TOP, w: OFFICE_W, d: OFFICE_D });
    for (const name of SHARED_ROOMS) expect(L.rooms[name].rect).toMatchObject({ z: SHARED_TOP, d: SHARED_D });
    expect(L.rooms.apple.desks).toHaveLength(12);
    expect(L.rooms.tools.desks).toHaveLength(7);
    expect(L.rooms.dock.desks).toHaveLength(4);
    expect(L.cubicles).toHaveLength(3);
    expect(L.cubicles[0].rect.z).toBe(FIRST_CUBICLE_Z);
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
    expect(L.rooms.apple.rect.w).toBe(3 + 6 * 4);
    expect(L.rooms.tools.rect.w).toBe(3 + 4 * 4);
    expect(L.rooms.dock.rect.w).toBe(3 + 2 * 4);
    expect(L.rooms.tools.rect.x).toBe(L.rooms.apple.rect.x + L.rooms.apple.rect.w + 1);
    for (const name of SHARED_ROOMS) {
      const room = L.rooms[name];
      for (const d of room.desks) {
        expect(inside(room.rect, d.seat)).toBe(true);
        expect(walk(L, d.desk)).toBe(false);
        expect(d.seat).toEqual({ x: d.desk.x + 1, z: d.desk.z + 2, facing: NORTH });
      }
    }
    // 7 个人：第一排 4 个，第二排 3 个
    const z = L.rooms.tools.desks.map(d => d.seat.z);
    expect(new Set(z.slice(0, 4)).size).toBe(1);
    expect(z[4]).toBeGreaterThan(z[0]);
  });

  it('a bigger dock room widens the office', () => {
    const L = computeLayout({ ...FULL, dock: 10 });
    expect(L.rooms.dock.desks).toHaveLength(10);
    expect(L.cols).toBe(2 * 2 + (3 + 6 * 4) + (3 + 4 * 4) + (3 + 5 * 4) + 2);
  });

  it('skips empty shared rooms and is never narrower than the facility band', () => {
    const L = computeLayout(NO_COUNTS);
    expect(L.cols).toBeGreaterThanOrEqual(MIN_COLS);
    expect(L.offices).toHaveLength(0);
    for (const name of SHARED_ROOMS) expect(L.rooms[name].desks).toHaveLength(0);
    expect(L.cubicles).toHaveLength(0);
  });

  it('builds exactly one cubicle per temp and adds rows as needed', () => {
    const L = computeLayout({ ...FULL, temp: 0 });
    expect(L.cubicleRows).toBe(1);
    const many = computeLayout({ ...FULL, temp: L.perRow + 1 });
    expect(many.cubicles).toHaveLength(L.perRow + 1);
    expect(many.cubicleRows).toBe(2);
    expect(many.rows).toBe(L.rows + 9);
    expect(many.cubicles[L.perRow].rect.z).toBe(FIRST_CUBICLE_Z + 9);
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
    for (const counts of [NO_COUNTS, FULL, { ...FULL, temp: 25 }, { office: 2, apple: 3, tools: 0, dock: 1, temp: 1 }]) {
      const L = computeLayout(counts);
      for (const s of spotsOf(L)) expect(walk(L, s), `${JSON.stringify(counts)} ${JSON.stringify(s)}`).toBe(true);
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
    for (const counts of [NO_COUNTS, FULL, { ...FULL, dock: 20 }]) {
      const L = computeLayout(counts);
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
    expect(computeLayout(NO_COUNTS).leisure.spots.length).toBeGreaterThanOrEqual(10);
    const spots = L.leisure.spots.map(s => `${s.x},${s.z}`);
    expect(new Set(spots).size).toBe(spots.length);
  });

  it('compares counts', () => {
    expect(sameCounts(FULL, { ...FULL })).toBe(true);
    expect(sameCounts(FULL, { ...FULL, temp: 4 })).toBe(false);
    expect(computeLayout(FULL).counts).toEqual(FULL);
  });

  it('uses half-metre cells', () => {
    expect(CELL).toBe(0.5);
  });
});
