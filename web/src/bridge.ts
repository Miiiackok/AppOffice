import type { InboundMessage, OutboundAction } from './protocol';

export interface OfficeWindow {
  office?: {
    receive(msg: InboundMessage | string): void;
    /** Swift 外壳转发的鼠标位置（窗口不是 key window 时网页收不到 mousemove）；null 是移出了窗口 */
    hover?(x: number | null, y: number | null): void;
  };
  webkit?: { messageHandlers?: { office?: { postMessage(action: OutboundAction): void } } };
}

export interface Bridge {
  post(action: OutboundAction): void;
  /** 收 Swift 转发来的鼠标位置 */
  onHover(handler: (x: number | null, y: number | null) => void): void;
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
  let hover: ((x: number | null, y: number | null) => void) | null = null;
  w.office = {
    hover(x, y) {
      hover?.(x, y);
    },
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
    onHover(handler) {
      hover = handler;
    },
  };
}
