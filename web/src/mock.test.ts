import { describe, expect, it } from 'vitest';
import { MockHost } from './mock';
import type { EmployeeStatus, InboundMessage } from './protocol';

function setup(random = () => 0.99) {
  const sent: InboundMessage[] = [];
  const host = new MockHost(m => sent.push(m), (name, color) => `${name}:${color}`, () => 1000, random);
  return { host, sent };
}
const statuses = (m: InboundMessage | undefined): EmployeeStatus[] => (m?.type === 'status' ? m.employees : []);

describe('MockHost', () => {
  it('ready sends the roster, then every status', () => {
    const { host, sent } = setup();
    host.handle({ action: 'ready' });
    expect(sent[0].type).toBe('roster');
    const roster = sent[0].type === 'roster' ? sent[0].employees : [];
    const seats = (room: number) => roster.filter(e => e.room === room).map(e => e.seat);
    expect(sent[0].type === 'roster' && sent[0].rooms.map(r => r.kind)).toEqual(['offices', 'shared', 'shared', 'shared']);
    expect(seats(0)).toEqual([0, 1, 2, 3]);
    expect(seats(1)).toEqual([...Array(12).keys()]);
    expect(seats(2)).toEqual([...Array(7).keys()]);
    expect(seats(3)).toEqual([0, 1, 2, 3]);
    expect(roster.filter(e => e.kind === 'temp').map(e => [e.room, e.seat])).toEqual([[null, null], [null, null], [null, null]]);
    expect(roster.find(e => e.room === 3 && e.seat === 0)).toMatchObject({ id: 'com.apple.finder', iconPNG: '访达:#3D7BFD' });
    expect(statuses(sent[1])).toHaveLength(30);
    expect(host.stateOf('mock.browser')).toBe('focused');
    expect(host.stateOf('mock.notes')).toBe('idle');
    expect(host.stateOf('mock.calendar')).toBe('off');
    expect(statuses(sent[1]).find(s => s.id === 'mock.notes')!.launchedAt).toBe(1000);
  });

  it('activate moves the focus', () => {
    const { host, sent } = setup();
    host.handle({ action: 'activate', id: 'mock.notes' });
    expect(host.stateOf('mock.notes')).toBe('focused');
    expect(host.stateOf('mock.browser')).toBe('idle');
    expect(statuses(sent.at(-1)).map(s => s.id).sort()).toEqual(['mock.browser', 'mock.notes']);
  });

  it('launch goes through launching, then takes focus after two ticks', () => {
    const { host } = setup();
    host.handle({ action: 'launch', id: 'mock.calendar' });
    expect(host.stateOf('mock.calendar')).toBe('launching');
    host.tick();
    expect(host.stateOf('mock.calendar')).toBe('launching');
    host.tick();
    expect(host.stateOf('mock.calendar')).toBe('focused');
    expect(host.stateOf('mock.browser')).toBe('idle');
  });

  it('activating an app that is not running launches it', () => {
    const { host } = setup();
    host.handle({ action: 'activate', id: 'mock.maps' });
    expect(host.stateOf('mock.maps')).toBe('launching');
  });

  it('quitting a temp removes it from the roster', () => {
    const { host, sent } = setup();
    host.handle({ action: 'quit', id: 'mock.video' });
    expect(host.rosterIDs()).not.toContain('mock.video');
    expect(sent.at(-1)!.type).toBe('roster');
  });

  it('quitting staff sends them back to slacking', () => {
    const { host, sent } = setup();
    host.handle({ action: 'quit', id: 'mock.mail' });
    expect(host.stateOf('mock.mail')).toBe('off');
    expect(statuses(sent.at(-1))[0]).toMatchObject({ id: 'mock.mail', launchedAt: null, cpu: 0 });
  });

  it('going offline sends running apps except Finder to the gym, and back', () => {
    const { host } = setup();
    host.setOffline(true);
    expect(host.network).toBe('offline');
    expect(host.stateOf('mock.browser')).toBe('offline');
    expect(host.stateOf('com.apple.finder')).toBe('idle');
    expect(host.stateOf('mock.calendar')).toBe('off');
    host.setOffline(false);
    expect(host.network).toBe('online');
    expect(host.stateOf('mock.browser')).toBe('focused');
  });

  it('hangs and unhangs', () => {
    const { host } = setup();
    const id = host.hangRandom()!;
    expect(host.stateOf(id)).toBe('hung');
    host.unhangAll();
    expect(host.stateOf(id)).toBe('idle');
  });

  it('snacks only idle or working apps', () => {
    const { host } = setup();
    const id = host.snackRandom()!;
    expect(host.stateOf(id)).toBe('snacking');
  });

  it('runs out of temps', () => {
    const { host } = setup();
    for (let i = 0; i < 4; i++) expect(host.addTemp()).not.toBeNull();
    expect(host.addTemp()).toBeNull();
    expect(host.removeTemp()).toBe('mock.video');
  });

  it('tick sometimes changes someone’s state', () => {
    const { host, sent } = setup(() => 0);
    const before = sent.length;
    host.tick();
    expect(sent.length).toBe(before + 1);
  });

  it('an app launching when the network drops waits at the gym, then finishes launching', () => {
    const { host } = setup();
    host.handle({ action: 'launch', id: 'mock.calendar' });
    host.setOffline(true);
    expect(host.stateOf('mock.calendar')).toBe('offline');
    host.tick(); host.tick(); host.tick();
    expect(host.stateOf('mock.calendar')).toBe('offline');
    host.setOffline(false);
    expect(host.stateOf('mock.calendar')).toBe('launching');
    host.tick(); host.tick();
    expect(host.stateOf('mock.calendar')).toBe('focused');
  });

  it('launching while offline goes straight to the gym', () => {
    const { host } = setup();
    host.setOffline(true);
    host.handle({ action: 'launch', id: 'mock.maps' });
    expect(host.stateOf('mock.maps')).toBe('offline');
    host.setOffline(false);
    expect(host.stateOf('mock.maps')).toBe('launching');
  });

  it('unhangAll with nobody hung sends nothing', () => {
    const { host, sent } = setup();
    const before = sent.length;
    host.unhangAll();
    expect(sent.length).toBe(before);
  });
});
