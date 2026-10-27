import { describe, expect, it, vi } from 'vitest';
import { hasNativeHost, installBridge, type OfficeWindow } from './bridge';
import type { InboundMessage, OutboundAction } from './protocol';

describe('bridge', () => {
  it('delivers object and JSON-string messages', () => {
    const w: OfficeWindow = {};
    const got: InboundMessage[] = [];
    installBridge(m => got.push(m), w);
    w.office!.receive({ type: 'paused', paused: true });
    w.office!.receive('{"type":"paused","paused":false}');
    expect(got).toEqual([{ type: 'paused', paused: true }, { type: 'paused', paused: false }]);
  });

  it('posts to the native handler when present', () => {
    const posted: OutboundAction[] = [];
    const w: OfficeWindow = { webkit: { messageHandlers: { office: { postMessage: a => posted.push(a) } } } };
    expect(hasNativeHost(w)).toBe(true);
    installBridge(() => {}, w).post({ action: 'ready' });
    expect(posted).toEqual([{ action: 'ready' }]);
  });

  it('an interceptor takes precedence over the native handler', () => {
    const native: OutboundAction[] = [];
    const local: OutboundAction[] = [];
    const w: OfficeWindow = { webkit: { messageHandlers: { office: { postMessage: a => native.push(a) } } } };
    const bridge = installBridge(() => {}, w);
    bridge.intercept(a => local.push(a));
    bridge.post({ action: 'quit', id: 'x' });
    bridge.intercept(null);
    bridge.post({ action: 'ready' });
    expect(local).toEqual([{ action: 'quit', id: 'x' }]);
    expect(native).toEqual([{ action: 'ready' }]);
  });

  it('logs to the console without a host', () => {
    const spy = vi.spyOn(console, 'info').mockImplementation(() => {});
    const w: OfficeWindow = {};
    expect(hasNativeHost(w)).toBe(false);
    installBridge(() => {}, w).post({ action: 'launch', id: 'x' });
    expect(spy).toHaveBeenCalledWith('[office] →', { action: 'launch', id: 'x' });
    spy.mockRestore();
  });

  it('receive never throws back into the host', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const w: OfficeWindow = {};
    const got: InboundMessage[] = [];
    installBridge(m => got.push(m), w);
    expect(() => w.office!.receive('not json')).not.toThrow();
    expect(got).toEqual([]);
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });

  it('passes forwarded mouse positions to the hover handler', () => {
    const w: OfficeWindow = {};
    const bridge = installBridge(() => {}, w);
    const seen: (number | null)[][] = [];
    w.office!.hover!(1, 2);
    bridge.onHover((x, y) => seen.push([x, y]));
    w.office!.hover!(10, 20);
    w.office!.hover!(null, null);
    expect(seen).toEqual([[10, 20], [null, null]]);
  });
});
