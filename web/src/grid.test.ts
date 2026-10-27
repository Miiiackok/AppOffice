import { describe, expect, it } from 'vitest';
import { findPath, type GridLike } from './grid';
import { computeLayout, spotsOf } from './layout';

function grid(lines: string[]): GridLike {
  const rows = lines.length, cols = lines[0].length;
  const walkable = new Uint8Array(cols * rows);
  lines.forEach((line, z) => [...line].forEach((ch, x) => { walkable[z * cols + x] = ch === '#' ? 0 : 1; }));
  return { cols, rows, walkable };
}

describe('findPath', () => {
  it('returns just the start when already there', () => {
    expect(findPath(grid(['...']), { x: 1, z: 0 }, { x: 1, z: 0 })).toEqual([{ x: 1, z: 0 }]);
  });

  it('walks a straight line', () => {
    expect(findPath(grid(['....']), { x: 0, z: 0 }, { x: 3, z: 0 }))
      .toEqual([{ x: 0, z: 0 }, { x: 1, z: 0 }, { x: 2, z: 0 }, { x: 3, z: 0 }]);
  });

  it('goes around a wall', () => {
    const g = grid(['.#.', '.#.', '...']);
    const p = findPath(g, { x: 0, z: 0 }, { x: 2, z: 0 })!;
    expect(p[0]).toEqual({ x: 0, z: 0 });
    expect(p.at(-1)).toEqual({ x: 2, z: 0 });
    for (const c of p) expect(g.walkable[c.z * 3 + c.x]).toBe(1);
    expect(p.some(c => c.z === 2)).toBe(true);
  });

  it('does not cut corners diagonally', () => {
    expect(findPath(grid(['.#', '..']), { x: 0, z: 0 }, { x: 1, z: 1 }))
      .toEqual([{ x: 0, z: 0 }, { x: 0, z: 1 }, { x: 1, z: 1 }]);
  });

  it('uses diagonals in open space', () => {
    expect(findPath(grid(['...', '...', '...']), { x: 0, z: 0 }, { x: 2, z: 2 })).toHaveLength(3);
  });

  it('returns null when the target is blocked or unreachable', () => {
    const g = grid(['.#.']);
    expect(findPath(g, { x: 0, z: 0 }, { x: 2, z: 0 })).toBeNull();
    expect(findPath(g, { x: 0, z: 0 }, { x: 1, z: 0 })).toBeNull();
  });

  it('can start from a blocked cell', () => {
    expect(findPath(grid(['#..']), { x: 0, z: 0 }, { x: 2, z: 0 })).toHaveLength(3);
  });

  it('returns null when the start is outside the grid', () => {
    const g = grid(['...', '...']);
    expect(findPath(g, { x: -1, z: 0 }, { x: 2, z: 0 })).toBeNull();
    expect(findPath(g, { x: 3, z: 0 }, { x: 0, z: 0 })).toBeNull();
    expect(findPath(g, { x: 0, z: -1 }, { x: 2, z: 0 })).toBeNull();
    expect(findPath(g, { x: 0, z: 2 }, { x: 2, z: 0 })).toBeNull();
  });

  it('returns null when the start is not an integer cell', () => {
    expect(findPath(grid(['...']), { x: 0.5, z: 0 }, { x: 2, z: 0 })).toBeNull();
  });

  it('reaches every spot in the office from the door', () => {
    const rooms = [{ name: 'A', desks: 12 }, { name: 'B', desks: 7 }, { name: 'C', desks: 4 }];
    const shapes = [
      { offices: 4, rooms, temp: 3 },
      { offices: 1, rooms: [{ name: 'A', desks: 0 }, { name: 'B', desks: 1 }, { name: 'C', desks: 9 }], temp: 0 },
      { offices: 7, rooms: [...rooms, ...rooms], temp: 20 },
    ];
    for (const counts of shapes) {
      const L = computeLayout(counts);
      for (const s of spotsOf(L)) expect(findPath(L, L.door, s), `${JSON.stringify(counts)} ${JSON.stringify(s)}`).not.toBeNull();
    }
  });
});
