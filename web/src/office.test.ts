import { describe, expect, it } from 'vitest';
import { OfficeModel } from './office';
import type { EmployeeState, EmployeeStatus, RoomInfo, RosterEmployee } from './protocol';

/** 和 Swift 发来的一样：第 0 间是大办公室那排，之后是小办公室 */
const ROOMS: RoomInfo[] = [
  { name: '大办公室', kind: 'offices' }, { name: '生活部', kind: 'shared' },
  { name: '办公部', kind: 'shared' }, { name: 'Dock 部', kind: 'shared' },
];
const OFFICE = 0, APPLE = 1, DOCK = 3;

const staff = (id: string, seat: number, room = APPLE): RosterEmployee =>
  ({ id, name: id, kind: 'staff', room, seat, color: '#123456', iconPNG: '' });
const temp = (id: string): RosterEmployee =>
  ({ id, name: id, kind: 'temp', room: null, seat: null, color: '#654321', iconPNG: '' });
const st = (id: string, state: EmployeeState, cpu = 0): EmployeeStatus =>
  ({ id, state, cpu, memMB: 0, launchedAt: null });
const staffList = (n: number) => Array.from({ length: n }, (_, i) => staff(`s${i}`, i));

describe('OfficeModel', () => {
  it('new staff sit at their desk in their room slacking', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [staff('a', 0), staff('b', 1), staff('c', 0, OFFICE), staff('d', 2, DOCK)]);
    expect(m.get('a')!.status.state).toBe('off');
    expect(m.target('b')).toEqual({ spot: m.layout.rooms[0].desks[1].seat, activity: 'slack', intensity: 0 });
    expect(m.target('c')!.spot).toEqual(m.layout.offices[0].desks[0].seat);
    expect(m.target('d')!.spot).toEqual(m.layout.rooms[2].desks[2].seat);
  });

  it('staff stay in their own room when they start working', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [staff('c', 0, OFFICE), staff('n', 0)]);
    m.applyStatus('online', [st('c', 'focused', 50), st('n', 'working', 30)]);
    expect(m.target('c')).toMatchObject({ spot: m.layout.offices[0].desks[0].seat, activity: 'type' });
    expect(m.target('n')).toMatchObject({ spot: m.layout.rooms[0].desks[0].seat, activity: 'type' });
  });

  it('new temps are launching in their own cubicle', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [temp('t')]);
    expect(m.get('t')!.status.state).toBe('launching');
    expect(m.target('t')).toEqual({ spot: m.layout.cubicles[0].seat, activity: 'boot', intensity: 0 });
  });

  it('every temp gets a cubicle of their own', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, Array.from({ length: 12 }, (_, i) => temp(`t${i}`)));
    expect(m.layout.cubicles).toHaveLength(12);
    const seats = Array.from({ length: 12 }, (_, i) => m.target(`t${i}`)!.spot);
    expect(new Set(seats.map(s => `${s.x},${s.z}`)).size).toBe(12);
    expect(m.target('t11')!.spot).toEqual(m.layout.cubicles[11].seat);
  });

  it('desk activity follows the state', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, staffList(5));
    m.applyStatus('online', [st('s0', 'focused', 90), st('s1', 'working', 30), st('s2', 'idle'), st('s3', 'launching'), st('s4', 'off')]);
    expect(m.target('s0')).toMatchObject({ activity: 'type', intensity: 0.9 });
    expect(m.target('s1')).toMatchObject({ activity: 'type', intensity: 0.3 });
    expect(m.target('s2')!.activity).toBe('idle');
    expect(m.target('s3')!.activity).toBe('boot');
    expect(m.target('s4')!.activity).toBe('slack');
  });

  it('hung apps go to the toilet and the third one queues', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, staffList(3));
    m.applyStatus('online', [st('s0', 'hung'), st('s1', 'hung'), st('s2', 'hung')]);
    expect(m.target('s0')).toMatchObject({ spot: m.layout.toilets[0], activity: 'toilet' });
    expect(m.target('s1')).toMatchObject({ spot: m.layout.toilets[1], activity: 'toilet' });
    expect(m.target('s2')).toMatchObject({ spot: m.layout.toiletQueue[0], activity: 'wait' });
  });

  it('leaving the toilet lets the queue in', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, staffList(3));
    m.applyStatus('online', [st('s0', 'hung'), st('s1', 'hung'), st('s2', 'hung')]);
    m.applyStatus('online', [st('s0', 'idle')]);
    expect(m.target('s2')).toMatchObject({ spot: m.layout.toilets[0], activity: 'toilet' });
    expect(m.target('s0')).toMatchObject({ spot: m.layout.rooms[0].desks[0].seat, activity: 'idle' });
  });

  it('offline apps run on treadmills, overflow does push-ups', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, staffList(4));
    m.applyStatus('offline', ['s0', 's1', 's2', 's3'].map(id => st(id, 'offline')));
    expect(m.network).toBe('offline');
    expect(m.target('s2')).toMatchObject({ spot: m.layout.treadmills[2], activity: 'run' });
    expect(m.target('s3')).toMatchObject({ spot: m.layout.gymMats[0], activity: 'pushup' });
  });

  it('snacking apps go to the pantry', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, staffList(1));
    m.applyStatus('online', [st('s0', 'snacking')]);
    expect(m.target('s0')).toMatchObject({ spot: m.layout.pantry[0], activity: 'eat' });
  });

  it('a long queue piles up on the last queue spot', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, staffList(8));
    m.applyStatus('online', staffList(8).map(e => st(e.id, 'hung')));
    expect(m.target('s7')!.spot).toEqual(m.layout.toiletQueue.at(-1));
  });

  it('a removed temp frees its cubicle for the next one, nobody else moves', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [temp('t0'), temp('t1'), temp('t2')]);
    const r = m.applyRoster(ROOMS, [temp('t1'), temp('t2')]);
    expect(r.removed).toEqual(['t0']);
    expect(m.get('t0')).toBeUndefined();
    expect(m.keyOf('t1')).toBe('temp:1');
    expect(m.ownerOf('temp:0')).toBeNull();
    m.applyRoster(ROOMS, [temp('t1'), temp('t2'), temp('t3')]);
    expect(m.keyOf('t3')).toBe('temp:0');
    expect(m.target('t3')!.spot).toEqual(m.layout.cubicles[0].seat);
  });

  it('reports added employees and layout changes', () => {
    const m = new OfficeModel();
    const first = m.applyRoster(ROOMS, staffList(5));
    expect(first.added).toHaveLength(5);
    expect(first.layoutChanged).toBe(true);
    expect(m.applyRoster(ROOMS, staffList(5)).layoutChanged).toBe(false);
    const second = m.applyRoster(ROOMS, [...staffList(5), temp('t')]);
    expect(second.added).toEqual(['t']);
    expect(second.layoutChanged).toBe(true);
    expect(m.layout.spec.temp).toBe(1);
    expect(m.layout.spec.rooms[0]).toEqual({ name: '生活部', desks: 5 });
  });

  it('a temp pinned to the Dock gives up its cubicle', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [temp('t')]);
    m.applyRoster(ROOMS, [staff('t', 4, DOCK), temp('u')]);
    expect(m.target('t')!.spot).toEqual(m.layout.rooms[2].desks[4].seat);
    expect(m.keyOf('u')).toBe('temp:0');
    expect(m.target('u')!.spot).toEqual(m.layout.cubicles[0].seat);
  });

  it('ignores status for unknown ids and finds desk owners', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [staff('a', 3), staff('c', 1, OFFICE), temp('t')]);
    m.applyStatus('online', [st('ghost', 'hung')]);
    expect(m.target('ghost')).toBeNull();
    expect(m.ownerOf('shared:0:3')).toBe('a');
    expect(m.ownerOf('office:1')).toBe('c');
    expect(m.ownerOf('temp:0')).toBe('t');
    expect(m.ownerOf('shared:0:0')).toBeNull();
  });

  it('long-unused apps go play in the leisure area and come back when opened', () => {
    const m = new OfficeModel(() => 0);
    m.applyRoster(ROOMS, [staff('a', 0), staff('b', 1)]);
    m.applyStatus('online', [st('a', 'resting'), st('b', 'resting')]);
    const spots = m.layout.leisure.spots;
    expect(m.target('a')).toEqual({ spot: spots[0], activity: 'arcade', intensity: 0 });
    expect(m.target('b')!.spot).toEqual(spots[1]);
    m.applyStatus('online', [st('a', 'launching')]);
    expect(m.target('a')).toMatchObject({ spot: m.layout.rooms[0].desks[0].seat, activity: 'boot' });
  });

  it('activities in the leisure area follow the spot', () => {
    const m = new OfficeModel(() => 0.999);
    m.applyRoster(ROOMS, [staff('a', 0)]);
    m.applyStatus('online', [st('a', 'resting')]);
    // 最后一个位置是懒人沙发
    expect(m.target('a')).toMatchObject({ spot: m.layout.leisure.spots.at(-1), activity: 'lounge' });
  });

  it('wandering moves someone resting to another spot', () => {
    const m = new OfficeModel(() => 0);
    m.applyRoster(ROOMS, [staff('a', 0)]);
    expect(m.wander()).toBe(false);
    m.applyStatus('online', [st('a', 'resting')]);
    const before = m.target('a')!.spot;
    expect(m.wander()).toBe(true);
    expect(m.target('a')!.spot).not.toEqual(before);
  });

  it('renaming or adding a room rebuilds the layout and keeps everyone seated', () => {
    const m = new OfficeModel();
    m.applyRoster(ROOMS, [staff('a', 0), staff('d', 0, DOCK)]);
    const renamed: RoomInfo[] = [ROOMS[0], { name: '新部门', kind: 'shared' }, ROOMS[2], ROOMS[3], { name: '游戏部', kind: 'shared' }];
    const r = m.applyRoster(renamed, [staff('a', 0), staff('d', 0, DOCK), staff('g', 0, 4)]);
    expect(r.layoutChanged).toBe(true);
    expect(m.layout.rooms.map(x => x.name)).toEqual(['新部门', '办公部', 'Dock 部', '游戏部']);
    expect(m.target('g')!.spot).toEqual(m.layout.rooms[3].desks[0].seat);
    expect(m.keyOf('g')).toBe('shared:3:0');
  });
});
