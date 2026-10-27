import { hasNativeHost, installBridge } from './bridge';
import { NameCard } from './card';
import { MockHost } from './mock';
import { mockIcon } from './mockIcons';
import { mountMockPanel } from './mockPanel';
import { runGallery } from './scene/gallery';
import { attachInteraction } from './scene/interaction';
import { runLayoutPreview } from './scene/layoutPreview';
import { OfficeApp } from './scene/officeApp';

const container = document.getElementById('app')!;
const params = new URLSearchParams(location.search);
if (params.has('gallery')) runGallery(container);
else if (params.has('layout')) runLayoutPreview(container, Number(params.get('layout')) || 5);
else startOffice();

function startOffice(): void {
  const app = new OfficeApp(container);
  const bridge = installBridge(msg => app.handle(msg));
  attachInteraction(app, action => bridge.post(action), new NameCard(container, app.model));
  // 不在 Swift 外壳里（或带 ?mock）就用假数据
  if (!hasNativeHost() || params.has('mock')) {
    const mock = new MockHost(msg => app.handle(msg), mockIcon);
    bridge.intercept(action => mock.handle(action));
    setInterval(() => mock.tick(), 1000);
    mountMockPanel(container, mock);
    (window as unknown as { mock: MockHost }).mock = mock;
    (window as unknown as { app: OfficeApp }).app = app;
  }
  bridge.post({ action: 'ready' });
  startLoop(app);
}

/** 30 帧；页面隐藏或 Swift 说暂停时停止渲染，每 250 毫秒看一眼要不要恢复 */
function startLoop(app: OfficeApp): void {
  let last = performance.now();
  let acc = 0;
  const loop = (now: number) => {
    if (app.paused || document.hidden) {
      last = now;
      setTimeout(() => requestAnimationFrame(loop), 250);
      return;
    }
    requestAnimationFrame(loop);
    acc += Math.max(0, (now - last) / 1000);
    last = now;
    // 卡太久就别补了
    if (acc > 0.25) acc = 0;
    // 留 2 毫秒余量，免得 60Hz 下刚好差一点被跳过
    if (acc < 1 / 30 - 0.002) return;
    // 按整帧推进，零头留到下一帧（低刷新率时一次推进多帧）
    const dt = Math.max(1, Math.floor((acc + 0.002) * 30)) / 30;
    app.frame(dt, now / 1000);
    acc -= dt;
  };
  requestAnimationFrame(loop);
}
