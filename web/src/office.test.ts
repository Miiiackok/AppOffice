import { describe, expect, it } from 'vitest';
import { OfficeModel } from './office';
import type { EmployeeState, EmployeeStatus, RoomName, RosterEmployee } from './protocol';

const staff = (id: string, seat: number, room: RoomName = 'apple'): RosterEmployee =>
  ({ id, name: id, kind: 'staff', room, seat, color: '#123456', iconPNG: '' });
const temp = (id: string): RosterEmployee =>
  ({ id, name: id, kind: 'temp', room: null, seat: null, color: '#654321', iconPNG: '' });
const st = (id: string, state: EmployeeState, cpu = 0): EmployeeStatus =>
  ({ id, state, cpu, memMB: 0, launchedAt: null });
const staffList = (n: number) => Array.from({ length: n }, (_, i) => staff(`s${i}`, i));

describe('OfficeModel', () => {
  it('new staff sit at their desk in their room slacking', () => {
    const m = new OfficeModel();
    m.applyRoster([staff('a', 0), staff('b', 1), staff('c', 0, 'office'), staff('d', 2, 'dock')]);
    expect(m.get('a')!.status.state).toBe('off');
    expect(m.target('b')).toEqual({ spot: m.layout.rooms.apple.desks[1].seat, activity: 'slack', intensity: 0 });
    expect(m.target('c')!.spot).toEqual(m.layout.offices[0].desks[0].seat);
    expect(m.target('d')!.spot).toEqual(m.layout.rooms.dock.desks[2].seat);
  });

  it('staff stay in their own room when they start working', () => {
    const m = new OfficeModel();
    m.applyRoster([staff('c', 0, 'office'), staff('n', 0)]);
    m.applyStatus('online', [st('c', 'focused', 50), st('n', 'working', 30)]);
    expect(m.target('c')).toMatchObject({ spot: m.layout.offices[0].desks[0].seat, activity: 'type' });
    expect(m.target('n')).toMatchObject({ spot: m.layout.rooms.apple.desks[0].seat, activity: 'type' });
  });

  it('new temps are launching in their own cubicle', () => {
    const m = new OfficeModel();
    m.applyRoster([temp('t')]);
    expect(m.get('t')!.status.state).toBe('launching');
    expect(m.target('t')).toEqual({ spot: m.layout.cubicles[0].seat, activity: 'boot', intensity: 0 });
  });

  it('every temp gets a cubicle of their own', () => {
    const m = new OfficeModel();
    m.applyRoster(Array.from({ length: 12 }, (_, i) => temp(`t${i}`)));
    expect(m.layout.cubicles).toHaveLength(12);
    const seats = Array.from({ length: 12 }, (_, i) => m.target(`t${i}`)!.spot);
    expect(new Set(seats.map(s => `${s.x},${s.z}`)).size).toBe(12);
    expect(m.target('t11')!.spot).toEqual(m.layout.cubicles[11].seat);
  });

  it('desk activity follows the state', () => {
    const m = new OfficeModel();
    m.applyRoster(staffList(5));
    m.applyStatus('online', [st('s0', 'focused', 90), st('s1', 'working', 30), st('s2', 'idle'), st('s3', 'launching'), st('s4', 'off')]);
    expect(m.target('s0')).toMatchObject({ activity: 'type', intensity: 0.9 });
    expect(m.target('s1')).toMatchObject({ activity: 'type', intensity: 0.3 });
    expect(m.target('s2')!.activity).toBe('idle');
    expect(m.target('s3')!.activity).toBe('boot');
    expect(m.target('s4')!.activity).toBe('slack');
  });

  it('hung apps go to the toilet and the third one queues', () => {
    const m = new OfficeModel();
    m.applyRoster(staffList(3));
    m.applyStatus('online', [st('s0', 'hung'), st('s1', 'hung'), st('s2', 'hung')]);
    expect(m.target('s0')).toMatchObject({ spot: m.layout.toilets[0], activity: 'toilet' });
    expect(m.target('s1')).toMatchObject({ spot: m.layout.toilets[1], activity: 'toilet' });
    expect(m.target('s2')).toMatchObject({ spot: m.layout.toiletQueue[0], activity: 'wait' });
  });

  it('leaving the toilet lets the queue in', () => {
    const m = new OfficeModel();
    m.applyRoster(staffList(3));
    m.applyStatus('online', [st('s0', 'hung'), st('s1', 'hung'), st('s2', 'hung')]);
    m.applyStatus('online', [st('s0', 'idle')]);
    expect(m.target('s2')).toMatchObject({ spot: m.layout.toilets[0], activity: 'toilet' });
    expect(m.target('s0')).toMatchObject({ spot: m.layout.rooms.apple.desks[0].seat, activity: 'idle' });
  });

  it('offline apps run on treadmills, overflow does push-ups', () => {
    const m = new OfficeModel();
    m.applyRoster(staffList(4));
    m.applyStatus('offline', ['s0', 's1', 's2', 's3'].map(id => st(id, 'offline')));
    expect(m.network).toBe('offline');
    expect(m.target('s2')).toMatchObject({ spot: m.layout.treadmills[2], activity: 'run' });
    expect(m.target('s3')).toMatchObject({ spot: m.layout.gymMats[0], activity: 'pushup' });
  });

  it('snacking apps go to the pantry', () => {
    const m = new OfficeModel();
    m.applyRoster(staffList(1));
    m.applyStatus('online', [st('s0', 'snacking')]);
    expect(m.target('s0')).toMatchObject({ spot: m.layout.pantry[0], activity: 'eat' });
  });

  it('a long queue piles up on the last queue spot', () => {
    const m = new OfficeModel();
    m.applyRoster(staffList(8));
    m.applyStatus('online', staffList(8).map(e => st(e.id, 'hung')));
    expect(m.target('s7')!.spot).toEqual(m.layout.toiletQueue.at(-1));
  });

  it('a removed temp frees its cubicle for the next one, nobody else moves', () => {
    const m = new OfficeModel();
    m.applyRoster([temp('t0'), temp('t1'), temp('t2')]);
    const r = m.applyRoster([temp('t1'), temp('t2')]);
    expect(r.removed).toEqual(['t0']);
    expect(m.get('t0')).toBeUndefined();
    expect(m.keyOf('t1')).toBe('temp:1');
    expect(m.ownerOf('temp:0')).toBeNull();
    m.applyRoster([temp('t1'), temp('t2'), temp('t3')]);
    expect(m.keyOf('t3')).toBe('temp:0');
    expect(m.target('t3')!.spot).toEqual(m.layout.cubicles[0].seat);
  });

  it('reports added employees and layout changes', () => {
    const m = new OfficeModel();
    const first = m.applyRoster(staffList(5));
    expect(first.added).toHaveLength(5);
    expect(first.layoutChanged).toBe(true);
    expect(m.applyRoster(staffList(5)).layoutChanged).toBe(false);
    const second = m.applyRoster([...staffList(5), temp('t')]);
    expect(second.added).toEqual(['t']);
    expect(second.layoutChanged).toBe(true);
    expect(m.layout.counts).toMatchObject({ apple: 5, temp: 1 });
  });

  it('a temp pinned to the Dock gives up its cubicle', () => {
    const m = new OfficeModel();
    m.applyRoster([temp('t')]);
    m.applyRoster([staff('t', 4, 'dock'), temp('u')]);
    expect(m.target('t')!.spot).toEqual(m.layout.rooms.dock.desks[4].seat);
    expect(m.keyOf('u')).toBe('temp:0');
    expect(m.target('u')!.spot).toEqual(m.layout.cubicles[0].seat);
  });

  it('ignores status for unknown ids and finds desk owners', () => {
    const m = new OfficeModel();
    m.applyRoster([staff('a', 3), staff('c', 1, 'office'), temp('t')]);
    m.applyStatus('online', [st('ghost', 'hung')]);
    expect(m.target('ghost')).toBeNull();
    expect(m.ownerOf('apple:3')).toBe('a');
    expect(m.ownerOf('office:1')).toBe('c');
    expect(m.ownerOf('temp:0')).toBe('t');
    expect(m.ownerOf('apple:0')).toBeNull();
  });

  it('long-unused apps go play in the leisure area and come back when opened', () => {
    const m = new OfficeModel(() => 0);
    m.applyRoster([staff('a', 0), staff('b', 1)]);
    m.applyStatus('online', [st('a', 'resting'), st('b', 'resting')]);
    const spots = m.layout.leisure.spots;
    expect(m.target('a')).toEqual({ spot: spots[0], activity: 'arcade', intensity: 0 });
    expect(m.target('b')!.spot).toEqual(spots[1]);
    m.applyStatus('online', [st('a', 'launching')]);
    expect(m.target('a')).toMatchObject({ spot: m.layout.rooms.apple.desks[0].seat, activity: 'boot' });
  });

  it('activities in the leisure area follow the spot', () => {
    const m = new OfficeModel(() => 0.999);
    m.applyRoster([staff('a', 0)]);
    m.applyStatus('online', [st('a', 'resting')]);
    // 最后一个位置是懒人沙发
    expect(m.target('a')).toMatchObject({ spot: m.layout.leisure.spots.at(-1), activity: 'lounge' });
  });

  it('wandering moves someone resting to another spot', () => {
    const m = new OfficeModel(() => 0);
    m.applyRoster([staff('a', 0)]);
    expect(m.wander()).toBe(false);
    m.applyStatus('online', [st('a', 'resting')]);
    const before = m.target('a')!.spot;
    expect(m.wander()).toBe(true);
    expect(m.target('a')!.spot).not.toEqual(before);
  });
});
