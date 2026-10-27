import * as THREE from 'three';
import { CELL, type Cell, type Rect } from '../layout';

const materials = new Map<string, THREE.MeshLambertMaterial>();
const unitBox = new THREE.BoxGeometry(1, 1, 1);

/** 同色共用一个材质；要单独改颜色的地方自己 new 材质 */
export function mat(color: string): THREE.MeshLambertMaterial {
  let m = materials.get(color);
  if (!m) {
    m = new THREE.MeshLambertMaterial({ color });
    materials.set(color, m);
  }
  return m;
}

/** 放一个方块，(x, y, z) 是底面中心，单位米 */
export function box(w: number, h: number, d: number, color: string | THREE.Material,
                    x: number, y: number, z: number): THREE.Mesh {
  const m = new THREE.Mesh(unitBox, typeof color === 'string' ? mat(color) : color);
  m.scale.set(w, h, d);
  m.position.set(x, y + h / 2, z);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}

/** 贴地的东西（地板、地毯、垫子）不投影 */
export function flat(m: THREE.Mesh): THREE.Mesh {
  m.castShadow = false;
  return m;
}

/** 格子中心 → 米 */
export function cellCenter(c: Cell): [number, number] {
  return [(c.x + 0.5) * CELL, (c.z + 0.5) * CELL];
}

export function rectCenter(r: Rect): [number, number] {
  return [(r.x + r.w / 2) * CELL, (r.z + r.d / 2) * CELL];
}

/** 一行字做成的精灵，宽 1 米高 0.25 米 */
export function textSprite(text: string, color: string): THREE.Sprite {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 64;
  const ctx = canvas.getContext('2d')!;
  ctx.font = '600 36px -apple-system, "PingFang SC", sans-serif';
  ctx.fillStyle = color;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, 128, 34);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false }));
  sprite.scale.set(1, 0.25, 1);
  return sprite;
}
