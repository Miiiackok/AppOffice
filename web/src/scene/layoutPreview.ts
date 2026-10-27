import { computeLayout } from '../layout';
import { buildOffice } from './builders';
import { createStage } from './stage';

const COLORS = ['#3D7BFD', '#E76F51', '#2A9D8F', '#F2C94C', '#9B51E0'];

/** ?layout=N：N 个临时工时的空办公室（房间按默认名单坐满） */
export function runLayoutPreview(container: HTMLElement, tempCount: number): void {
  const stage = createStage(container);
  const rooms = [{ name: '生活部', desks: 12 }, { name: '办公部', desks: 7 }, { name: 'Dock 部', desks: 4 }];
  const office = buildOffice(computeLayout({ offices: 4, rooms, temp: tempCount }));
  stage.scene.add(office.group);
  [...office.decor.values()].forEach((d, i) => {
    d.setOwner(COLORS[i % COLORS.length], null);
    d.setScreen(i % 3 !== 0);
  });
  stage.frame(office.bounds);
  const loop = () => {
    requestAnimationFrame(loop);
    stage.render();
  };
  loop();
}
