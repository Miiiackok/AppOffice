import * as THREE from 'three';
import type { NameCard } from '../card';
import { isClosed } from '../office';
import type { OutboundAction } from '../protocol';
import type { OfficeApp } from './officeApp';

/** 移动超过这么多像素才算拖动 */
const DRAG_THRESHOLD = 5;
/** 放在大门这么近（米）就算送走 */
const DOOR_RADIUS = 1.4;
const ROTATE_SPEED = 0.005;

/** 返回一个函数，给 Swift 外壳转发的鼠标位置用（窗口坐标，null 是移出窗口） */
export function attachInteraction(app: OfficeApp, post: (action: OutboundAction) => void, card: NameCard):
  (x: number | null, y: number | null) => void {
  const el = app.renderer.domElement;
  const ray = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  const floor = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  const hit = new THREE.Vector3();
  let down: { x: number; y: number; agentId: string | null } | null = null;
  let mode: 'none' | 'rotate' | 'drag' = 'none';
  let lastX = 0;

  const aim = (e: MouseEvent) => {
    const r = el.getBoundingClientRect();
    ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(ndc, app.rig.camera);
  };
  const pickAgent = (): string | null => {
    for (const h of ray.intersectObjects(app.agentRoots(), true)) {
      for (let o: THREE.Object3D | null = h.object; o; o = o.parent) {
        if (typeof o.userData.agentId === 'string') return o.userData.agentId;
      }
    }
    return null;
  };
  const pickDesk = (): string | null => {
    const h = ray.intersectObjects(app.seatHitBoxes(), false)[0];
    return h ? (h.object.userData.desk as string) : null;
  };
  const openOrFocus = (id: string) => {
    const e = app.model.get(id);
    if (e) post({ action: isClosed(e.status.state) ? 'launch' : 'activate', id });
  };

  el.addEventListener('pointerdown', e => {
    aim(e);
    down = { x: e.clientX, y: e.clientY, agentId: pickAgent() };
    mode = 'none';
    lastX = e.clientX;
    el.setPointerCapture(e.pointerId);
  });

  /** 鼠标没按着时停在谁身上就弹谁的名片 */
  const hoverAt = (clientX: number | null, clientY: number | null) => {
    if (down) return;
    if (clientX === null || clientY === null) return card.hover(null, 0, 0);
    aim({ clientX, clientY } as MouseEvent);
    card.hover(pickAgent(), clientX, clientY);
  };

  el.addEventListener('pointerleave', () => hoverAt(null, null));
  el.addEventListener('pointermove', e => {
    if (!down) return hoverAt(e.clientX, e.clientY);
    if (mode === 'none' && Math.hypot(e.clientX - down.x, e.clientY - down.y) > DRAG_THRESHOLD) {
      mode = down.agentId ? 'drag' : 'rotate';
      card.hide();
    }
    if (mode === 'rotate') {
      app.rig.rotateBy(-(e.clientX - lastX) * ROTATE_SPEED);
      lastX = e.clientX;
    } else if (mode === 'drag' && down.agentId) {
      aim(e);
      if (ray.ray.intersectPlane(floor, hit)) app.dragAgent(down.agentId, hit);
    }
  });

  /** 松手或指针丢了。cancelled 时不弹名片、不送走，只是放下 */
  const release = (e: PointerEvent, cancelled: boolean) => {
    if (!down) return;
    const d = down;
    const m = mode;
    down = null;
    mode = 'none';
    if (m === 'drag' && d.agentId) {
      const atDoor = app.dropAgent(d.agentId, DOOR_RADIUS);
      const emp = app.model.get(d.agentId);
      if (!cancelled && atDoor && emp && !isClosed(emp.status.state)) post({ action: 'quit', id: d.agentId });
      return;
    }
    if (m === 'none' && !cancelled) {
      if (d.agentId) card.show(d.agentId, e.clientX, e.clientY);
      else card.hide();
    }
  };
  el.addEventListener('pointerup', e => release(e, false));
  el.addEventListener('pointercancel', e => release(e, true));
  el.addEventListener('lostpointercapture', e => release(e, true));

  el.addEventListener('dblclick', e => {
    aim(e);
    const id = pickAgent();
    if (id) return openOrFocus(id);
    const desk = pickDesk();
    const owner = desk === null ? null : app.model.ownerOf(desk);
    if (owner) return openOrFocus(owner);
    app.rig.reset();
  });

  el.addEventListener('wheel', e => {
    e.preventDefault();
    app.rig.zoomBy(Math.exp(e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)));
  }, { passive: false });

  window.addEventListener('keydown', e => {
    if (e.key === 'Escape') card.hide();
  });

  return hoverAt;
}
