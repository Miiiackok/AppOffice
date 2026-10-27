import type { InboundMessage, OutboundAction } from './protocol';

export interface OfficeWindow {
  office?: { receive(msg: InboundMessage | string): void };
  webkit?: { messageHandlers?: { office?: { postMessage(action: OutboundAction): void } } };
}

export interface Bridge {
  post(action: OutboundAction): void;
  /** mock 模式下把操作请求转给 MockHost；传 null 取消 */
  intercept(handler: ((action: OutboundAction) => void) | null): void;
}

const globalWindow = (): OfficeWindow => globalThis as unknown as OfficeWindow;

export function hasNativeHost(w: OfficeWindow = globalWindow()): boolean {
  return !!w.webkit?.messageHandlers?.office;
}

/** Swift 调 window.office.receive(...) 推消息；网页用 post 发操作请求 */
export function installBridge(onMessage: (msg: InboundMessage) => void, w: OfficeWindow = globalWindow()): Bridge {
  let interceptor: ((action: OutboundAction) => void) | null = null;
  w.office = {
    receive(msg) {
      try {
        onMessage(typeof msg === 'string' ? (JSON.parse(msg) as InboundMessage) : msg);
      } catch (err) {
        console.error('[office] bad message', msg, err);
      }
    },
  };
  return {
    post(action) {
      if (interceptor) {
        interceptor(action);
        return;
      }
      const native = w.webkit?.messageHandlers?.office;
      if (native) native.postMessage(action);
      else console.info('[office] →', action);
    },
    intercept(handler) {
      interceptor = handler;
    },
  };
}
