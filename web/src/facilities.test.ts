import { describe, expect, it } from 'vitest';
import { Facility, Roaming } from './facilities';

const seat = (index: number) => ({ kind: 'seat', index });
const queue = (index: number) => ({ kind: 'queue', index });

describe('Facility', () => {
  it('seats people until full, then queues', () => {
    const f = new Facility(2);
    for (const id of ['a', 'b', 'c', 'd']) f.join(id);
    expect(f.placeOf('a')).toEqual(seat(0));
    expect(f.placeOf('b')).toEqual(seat(1));
    expect(f.placeOf('c')).toEqual(queue(0));
    expect(f.placeOf('d')).toEqual(queue(1));
  });

  it('moves the head of the queue into the freed seat', () => {
    const f = new Facility(2);
    for (const id of ['a', 'b', 'c', 'd']) f.join(id);
    f.leave('a');
    expect(f.placeOf('a')).toBeNull();
    expect(f.placeOf('c')).toEqual(seat(0));
    expect(f.placeOf('b')).toEqual(seat(1));
    expect(f.placeOf('d')).toEqual(queue(0));
  });

  it('keeps seat indices stable', () => {
    const f = new Facility(3);
    for (const id of ['a', 'b', 'c']) f.join(id);
    f.leave('b');
    expect(f.placeOf('c')).toEqual(seat(2));
    f.join('x');
    expect(f.placeOf('x')).toEqual(seat(1));
  });

  it('leaving from the queue moves those behind forward', () => {
    const f = new Facility(1);
    for (const id of ['a', 'b', 'c']) f.join(id);
    f.leave('b');
    expect(f.placeOf('c')).toEqual(queue(0));
  });

  it('ignores duplicate joins and unknown leaves', () => {
    const f = new Facility(1);
    f.join('a');
    f.join('a');
    f.leave('nobody');
    expect(f.placeOf('a')).toEqual(seat(0));
    expect(f.members()).toEqual(['a']);
  });

  it('with no seats everyone queues', () => {
    const f = new Facility(0);
    f.join('a');
    expect(f.placeOf('a')).toEqual(queue(0));
  });

  it('lists seated members by seat, then the queue', () => {
    const f = new Facility(2);
    for (const id of ['a', 'b', 'c']) f.join(id);
    f.leave('a');
    expect(f.members()).toEqual(['c', 'b']);
  });
});

describe('Roaming', () => {
  // 每次取第一个
  const first = () => 0;

  it('gives everyone a free spot and moves one person to another free spot', () => {
    const r = new Roaming(3, first);
    r.join('a');
    r.join('b');
    expect([r.placeOf('a'), r.placeOf('b')]).toEqual([0, 1]);
    expect(r.wander()).toBe('a');
    expect(r.placeOf('a')).toBe(2);
    r.leave('b');
    expect(r.placeOf('b')).toBeUndefined();
  });

  it('crowds onto the last spot when full and does not wander', () => {
    const r = new Roaming(1, first);
    r.join('a');
    r.join('b');
    expect(r.placeOf('b')).toBe(1);
    expect(r.wander()).toBeNull();
  });

  it('re-seats people whose spot disappears', () => {
    const r = new Roaming(4, () => 0.99);
    r.join('a');
    expect(r.placeOf('a')).toBe(3);
    r.resize(2);
    expect(r.placeOf('a')).toBe(1);
  });

  it('does nothing with nobody there', () => {
    expect(new Roaming(3, first).wander()).toBeNull();
  });
});
