import * as THREE from 'three';
import { CELL, CUBICLE, type Cubicle, type Desk, type Layout, type Office, type Room } from '../layout';
import { PALETTE as P } from './palette';
import { box, cellCenter, flat, rectCenter } from './util';

export interface CubicleDecor {
  /** 地毯描边、看板换成主人的颜色和图标；null 表示空工位 */
  setOwner(color: string | null, icon: THREE.Texture | null): void;
  setScreen(on: boolean): void;
}

export interface OfficeStatic {
  group: THREE.Group;
  /** 按工位名（office:0、shared:1:3、temp:2，见 OfficeModel.keyOf）索引 */
  decor: Map<string, CubicleDecor>;
  /** 双击工位用的隐形碰撞盒，userData.desk 是工位名 */
  seatHitBoxes: THREE.Mesh[];
  bounds: THREE.Box3;
  /** 释放每个工位自己的材质；共用的几何体和材质不动 */
  dispose(): void;
}

// 几何体和隐形材质全办公室共用
const screenGeo = new THREE.PlaneGeometry(0.56, 0.34);
const unitPlane = new THREE.PlaneGeometry(1, 1);
const hitGeo = new THREE.BoxGeometry(1, 1, 1);
const hitMat = new THREE.MeshBasicMaterial({ visible: false });
/** 看板往后仰，正对高处的相机 */
const BOARD_TILT = THREE.MathUtils.degToRad(20);
/** 图标占看板边框的 6/7 */
const ICON_RATIO = 6 / 7;
const GLASS_H = 1.3;
const glassMat = new THREE.MeshLambertMaterial({ color: P.glass, transparent: true, opacity: 0.3, depthWrite: false });
/** 自己发光的屏幕（游戏机、电视），同色共用 */
const glowMats = new Map<string, THREE.MeshBasicMaterial>();
const glow = (color: string) => {
  let m = glowMats.get(color);
  if (!m) glowMats.set(color, (m = new THREE.MeshBasicMaterial({ color })));
  return m;
};

/** 一个工位长什么样，单位米 */
interface StationSpec {
  /** 桌面宽、深 */
  top: [number, number];
  monitors: number;
  /** 主人颜色的地毯，以椅子的 x 为中心 */
  rug: { w: number; d: number; z: number };
  /** 地上印的主人图标，以椅子的 x 为中心 */
  logo: { size: number; z: number };
  /** 看板：组的原点在 (x, y, z)，边框上沿高出原点 above */
  board: { size: number; above: number; x: number; y: number; z: number; tilt: number };
  plant: boolean;
  hit: { x: number; z: number; w: number; d: number };
}

interface Station {
  decor: CubicleDecor;
  hit: THREE.Mesh;
  materials: THREE.Material[];
}

/** 用方块拼出整个办公室（不含小人） */
export function buildOffice(L: Layout): OfficeStatic {
  const g = new THREE.Group();
  const W = L.cols * CELL, D = L.rows * CELL;
  g.add(flat(box(W, 0.02, D, P.floor, W / 2, -0.02, D / 2)));
  const zones = [[L.zones.toilet, P.toiletFloor], [L.zones.gym, P.gymFloor],
    [L.zones.pantry, P.pantryFloor], [L.zones.leisure, P.leisureFloor], [L.zones.open, P.openFloor]] as const;
  for (const [rect, color] of zones) {
    const [x, z] = rectCenter(rect);
    g.add(flat(box(rect.w * CELL, 0.01, rect.d * CELL, color, x, 0, z)));
  }
  buildWalls(g, L);

  const decor = new Map<string, CubicleDecor>();
  const seatHitBoxes: THREE.Mesh[] = [];
  const owned: THREE.Material[] = [];
  const add = (key: string, s: Station) => {
    s.hit.userData.desk = key;
    decor.set(key, s.decor);
    seatHitBoxes.push(s.hit);
    owned.push(...s.materials);
  };
  // 设施牌子和小办公室门牌的贴图是自己画的，拆办公室时一起释放
  const signTextures: THREE.Texture[] = [];
  const sign = (text: string, x: number, y: number, z: number) => {
    const made = addSign(g, text, x, y, z);
    owned.push(made.material);
    signTextures.push(made.texture);
  };
  L.offices.forEach((o, i) => add(`office:${i}`, buildPrivateOffice(g, o)));
  L.rooms.forEach((room, r) => {
    if (room.desks.length === 0) return;
    buildGlassRoom(g, room, P.roomFloor);
    room.desks.forEach((d, i) => add(`shared:${r}:${i}`, buildSharedDesk(g, d)));
    // 门牌立在北墙玻璃顶上
    sign(room.name, rectCenter(room.rect)[0], GLASS_H, (room.rect.z + 0.5) * CELL + 0.03);
  });
  L.cubicles.forEach((c, i) => {
    add(`temp:${i}`, buildCubicle(g, c, i));
    // 每排最后一个隔间右边的挡板
    if (i % L.perRow === L.perRow - 1 || i === L.cubicles.length - 1) {
      g.add(box(0.06, 1.1, c.rect.d * CELL, P.partition, (c.rect.x + c.rect.w + 0.5) * CELL, 0, (c.rect.z + c.rect.d / 2) * CELL));
    }
  });

  buildToilet(g, L);
  buildGym(g, L);
  buildPantry(g, L);
  buildLeisure(g, L);
  // 设施牌子挂在后墙顶上
  const facilities = [[L.zones.toilet, '洗手间'], [L.zones.gym, '健身房'], [L.zones.pantry, '茶水间'], [L.zones.leisure, '休闲区']] as const;
  for (const [zone, text] of facilities) sign(text, rectCenter(zone)[0], 1.55, 0.08);
  const bounds = new THREE.Box3(new THREE.Vector3(-0.3, 0, -0.3), new THREE.Vector3(W + 0.3, 1.6, D + 0.3));
  return {
    group: g, decor, seatHitBoxes, bounds,
    dispose() {
      for (const m of owned) m.dispose();
      for (const t of signTextures) t.dispose();
    },
  };
}

function buildWalls(g: THREE.Group, L: Layout): void {
  const W = L.cols * CELL, D = L.rows * CELL;
  g.add(box(W + 0.2, 1.6, 0.1, P.wall, W / 2, 0, -0.05));
  g.add(box(0.1, 0.5, D, P.wall, -0.05, 0, D / 2));
  g.add(box(0.1, 0.5, D, P.wall, W + 0.05, 0, D / 2));
  // 前墙矮一点，大门处留口
  const [doorX] = cellCenter(L.door);
  const left = doorX - 0.6, right = doorX + 0.6;
  g.add(box(left, 0.3, 0.1, P.wall, left / 2, 0, D + 0.05));
  g.add(box(W - right, 0.3, 0.1, P.wall, (W + right) / 2, 0, D + 0.05));
  g.add(box(0.1, 2.1, 0.12, P.door, left + 0.05, 0, D + 0.05));
  g.add(box(0.1, 2.1, 0.12, P.door, right - 0.05, 0, D + 0.05));
  g.add(box(1.2, 0.1, 0.12, P.door, doorX, 2.1, D + 0.05));
  const door = box(1.0, 2.0, 0.05, P.door, 0, 0, 0);
  door.position.set(left + 0.1, 1.0, D + 0.55);
  door.rotation.y = Math.PI / 2;
  g.add(door);
  g.add(flat(box(1.0, 0.012, 0.6, P.doormat, doorX, 0, D - 0.35)));
  addPlant(g, left - 0.4, D - 0.4, 1.4);
  addPlant(g, 0.4, D - 0.4, 1.2);
  addPlant(g, W - 0.4, (L.zones.toilet.d + 1.5) * CELL, 1.2);
}

/** 玻璃墙 + 地板；墙立在边上那圈格子的中线上，南墙留门 */
function buildGlassRoom(g: THREE.Group, r: Room, floor: string): void {
  const west = (r.rect.x + 0.5) * CELL, east = (r.rect.x + r.rect.w - 0.5) * CELL;
  const north = (r.rect.z + 0.5) * CELL, south = (r.rect.z + r.rect.d - 0.5) * CELL;
  g.add(flat(box(east - west, 0.008, south - north, floor, (west + east) / 2, 0, (north + south) / 2)));
  const doorL = r.door.x * CELL, doorR = (r.door.x + r.door.w) * CELL;
  addGlass(g, west, north, east, north);
  addGlass(g, west, north, west, south);
  addGlass(g, east, north, east, south);
  addGlass(g, west, south, doorL, south);
  addGlass(g, doorR, south, east, south);
  for (const [x, z] of [[west, north], [east, north], [west, south], [east, south], [doorL, south], [doorR, south]]) {
    g.add(box(0.07, GLASS_H + 0.05, 0.07, P.glassFrame, x, 0, z));
  }
}

/** 一段沿 x 或 z 方向的玻璃：透明玻璃、顶框、踢脚 */
function addGlass(g: THREE.Group, x1: number, z1: number, x2: number, z2: number): void {
  const alongX = z1 === z2;
  const len = alongX ? x2 - x1 : z2 - z1;
  if (len <= 0) return;
  const cx = (x1 + x2) / 2, cz = (z1 + z2) / 2;
  const size = (t: number): [number, number] => (alongX ? [len, t] : [t, len]);
  const [gw, gd] = size(0.04);
  const glass = box(gw, GLASS_H, gd, glassMat, cx, 0, cz);
  glass.castShadow = false;
  g.add(glass);
  const [fw, fd] = size(0.06);
  g.add(box(fw, 0.05, fd, P.glassFrame, cx, GLASS_H, cz));
  g.add(box(fw, 0.06, fd, P.glassFrame, cx, 0, cz));
}

/** 大办公室：玻璃墙、大桌子两台显示器、墙上大看板、书架、沙发、角落盆栽 */
function buildPrivateOffice(g: THREE.Group, o: Office): Station {
  buildGlassRoom(g, o, P.officeFloor);
  const r = o.rect;
  const d = o.desks[0];
  const [dx] = rectCenter(d.desk);
  const [, sz] = cellCenter(d.seat);
  const station = buildStation(g, d, {
    top: [2.5, 1.0],
    monitors: 2,
    rug: { w: 2.8, d: 2.6, z: sz },
    logo: { size: 0.95, z: sz + 0.775 },
    board: { size: 1.0, above: 0.25, x: dx, y: GLASS_H, z: (r.z + 0.5) * CELL + 0.04, tilt: BOARD_TILT },
    plant: false,
    hit: { x: (r.x + r.w / 2) * CELL, z: (r.z + r.d / 2) * CELL, w: r.w * CELL - 0.6, d: r.d * CELL - 0.6 },
  });

  // 沙发靠东墙，面朝西
  const s = o.sofa;
  const [, scz] = rectCenter(s);
  const sx0 = s.x * CELL, sx1 = (s.x + s.w) * CELL, len = s.d * CELL;
  g.add(box(0.3, 0.8, len, P.sofa, sx1 - 0.15, 0, scz));
  g.add(box(0.7, 0.38, len, P.sofa, sx0 + 0.35, 0, scz));
  for (const oz of [-0.47, 0.47]) g.add(box(0.55, 0.08, 0.85, P.sofaCushion, sx0 + 0.32, 0.38, scz + oz));

  // 书架靠西墙，书朝东
  const b = o.shelf;
  const [bx, bz] = rectCenter(b);
  g.add(box(0.42, 1.5, b.d * CELL - 0.1, P.shelf, bx, 0, bz));
  [0.3, 0.75, 1.2].forEach((y, level) => {
    for (let j = 0; j < 4; j++) {
      g.add(box(0.1, 0.3, 0.16, P.books[(level + j) % P.books.length], bx + 0.2, y, bz - 0.45 + j * 0.3));
    }
  });

  addPlant(g, (r.x + 1.5) * CELL, (r.z + r.d - 1.5) * CELL, 1.0);
  return station;
}

/** 合用办公室里的一张小桌子：没有挡板，看板是立在桌上的小牌子 */
function buildSharedDesk(g: THREE.Group, d: Desk): Station {
  const [dx, dz] = rectCenter(d.desk);
  const [, sz] = cellCenter(d.seat);
  return buildStation(g, d, {
    top: [1.35, 0.85],
    monitors: 1,
    rug: { w: 1.6, d: 1.4, z: sz + 0.2 },
    logo: { size: 0.6, z: sz + 0.55 },
    board: { size: 0.32, above: 0.32, x: dx - 0.47, y: 0.75, z: dz - 0.2, tilt: THREE.MathUtils.degToRad(15) },
    plant: false,
    hit: { x: dx, z: dz + 0.75, w: 1.9, d: 2.4 },
  });
}

/** 临时工的隔间：后挡板、左挡板，看板挂在后挡板顶上 */
function buildCubicle(g: THREE.Group, c: Cubicle, index: number): Station {
  const x0 = c.rect.x * CELL, z0 = c.rect.z * CELL, size = CUBICLE * CELL;
  // 后挡板、左挡板 + 顶上的压条
  g.add(box(size, 1.1, 0.06, P.partition, x0 + size / 2, 0, z0 + CELL / 2));
  g.add(box(0.06, 1.1, size, P.partition, x0 + CELL / 2, 0, z0 + size / 2));
  g.add(box(size, 0.04, 0.08, P.partitionTrim, x0 + size / 2, 1.1, z0 + CELL / 2));
  g.add(box(0.08, 0.04, size, P.partitionTrim, x0 + CELL / 2, 1.1, z0 + size / 2));
  const LOGO = 0.88;
  return buildStation(g, c, {
    top: [2.4, 0.9],
    monitors: 1,
    rug: { w: 2.3, d: 2.3, z: z0 + 1.75 },
    // 椅子后面（靠背最远到 z0+2.02）到地毯外沿（z0+2.9）之间
    logo: { size: LOGO, z: z0 + 2.9 - LOGO / 2 },
    // 上沿搭在后挡板压条上、往后仰，下沿离桌子还有空；在显示器左边
    board: { size: 0.7, above: 0.19, x: x0 + 0.75, y: 1.14, z: z0 + CELL / 2 + 0.04, tilt: BOARD_TILT },
    plant: index % 2 === 0,
    hit: { x: x0 + size / 2 + 0.1, z: z0 + size / 2 + 0.1, w: size - 0.3, d: size - 0.3 },
  });
}

/** 地毯、桌子、显示器、键盘、椅子、看板、地上的图标、点击盒 */
function buildStation(g: THREE.Group, d: Desk, s: StationSpec): Station {
  const [sx, sz] = cellCenter(d.seat);
  const [dx, dz] = rectCenter(d.desk);

  // 地毯：外圈是主人的颜色
  const rugMat = new THREE.MeshLambertMaterial({ color: P.rugEmpty });
  g.add(flat(box(s.rug.w, 0.012, s.rug.d, rugMat, sx, 0, s.rug.z)));
  g.add(flat(box(s.rug.w - 0.3, 0.016, s.rug.d - 0.3, P.rugInner, sx, 0, s.rug.z)));

  // 桌子、显示器、键盘、桌上小盆栽
  const [tw, td] = s.top;
  g.add(box(tw, 0.05, td, P.deskTop, dx, 0.7, dz));
  for (const ox of [-1, 1]) for (const oz of [-1, 1]) {
    g.add(box(0.05, 0.7, 0.05, P.deskLeg, dx + ox * (tw / 2 - 0.08), 0, dz + oz * (td / 2 - 0.07)));
  }
  const screenMat = new THREE.MeshBasicMaterial({ color: P.screenOff });
  for (let i = 0; i < s.monitors; i++) {
    const mx = dx + (i - (s.monitors - 1) / 2) * 0.68;
    const mz = dz - td / 2 + 0.2;
    g.add(box(0.08, 0.2, 0.08, P.monitor, mx, 0.75, mz));
    g.add(box(0.62, 0.4, 0.05, P.monitor, mx, 0.92, mz));
    const screen = new THREE.Mesh(screenGeo, screenMat);
    screen.position.set(mx, 1.12, mz + 0.03);
    g.add(screen);
  }
  g.add(box(0.5, 0.02, 0.16, P.keyboard, dx, 0.75, dz + td / 2 - 0.25));
  if (s.plant) {
    g.add(box(0.14, 0.14, 0.14, P.plantPot, dx + tw / 2 - 0.2, 0.75, dz - 0.25));
    g.add(box(0.2, 0.2, 0.2, P.plantLeaf, dx + tw / 2 - 0.2, 0.89, dz - 0.25));
  }

  addChair(g, sx, sz, d.seat.facing);

  const b = s.board;
  const board = new THREE.Group();
  board.position.set(b.x, b.y, b.z);
  board.rotation.x = -b.tilt;
  board.add(box(b.size, b.size, 0.03, P.boardFrame, 0, b.above - b.size, 0.015));
  const iconMat = new THREE.MeshBasicMaterial({ color: '#FFFFFF', transparent: true });
  const icon = new THREE.Mesh(unitPlane, iconMat);
  icon.scale.setScalar(b.size * ICON_RATIO);
  icon.position.set(0, b.above - b.size / 2, 0.035);
  icon.visible = false;
  board.add(icon);
  g.add(board);

  const logoMat = new THREE.MeshBasicMaterial({
    color: '#FFFFFF', transparent: true, depthWrite: false,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  });
  const logo = new THREE.Mesh(unitPlane, logoMat);
  logo.scale.setScalar(s.logo.size);
  logo.rotation.x = -Math.PI / 2;
  logo.position.set(sx, 0.02, s.logo.z);
  logo.visible = false;
  g.add(logo);

  const hit = new THREE.Mesh(hitGeo, hitMat);
  hit.scale.set(s.hit.w, 1.2, s.hit.d);
  hit.position.set(s.hit.x, 0.6, s.hit.z);
  g.add(hit);

  return {
    hit,
    materials: [rugMat, screenMat, iconMat, logoMat],
    decor: {
      setOwner(color, tex) {
        rugMat.color.set(color ?? P.rugEmpty);
        // 贴图真换了才让材质重编译
        for (const m of [iconMat, logoMat]) {
          if (m.map !== tex) {
            m.map = tex;
            m.needsUpdate = true;
          }
        }
        icon.visible = logo.visible = tex !== null;
      },
      setScreen(on) {
        screenMat.color.set(on ? P.screenOn : P.screenOff);
      },
    },
  };
}

/** 椅子；facing 是坐的人面朝的方向，靠背在他身后 */
function addChair(g: THREE.Group, x: number, z: number, facing: number): void {
  const c = new THREE.Group();
  c.position.set(x, 0, z);
  c.rotation.y = facing;
  c.add(box(0.46, 0.06, 0.46, P.chair, 0, 0.4, 0));
  c.add(box(0.46, 0.5, 0.06, P.chair, 0, 0.46, -0.24));
  c.add(box(0.06, 0.4, 0.06, P.chairBase, 0, 0, 0));
  c.add(box(0.5, 0.04, 0.08, P.chairBase, 0, 0, 0));
  c.add(box(0.08, 0.04, 0.5, P.chairBase, 0, 0, 0));
  g.add(c);
}

function addPlant(g: THREE.Group, x: number, z: number, s: number): void {
  g.add(box(0.3 * s, 0.3 * s, 0.3 * s, P.plantPot, x, 0, z));
  g.add(box(0.45 * s, 0.4 * s, 0.45 * s, P.plantLeaf, x, 0.3 * s, z));
  g.add(box(0.3 * s, 0.3 * s, 0.3 * s, P.plantLeafDark, x + 0.05 * s, 0.65 * s, z - 0.03 * s));
}

function buildToilet(g: THREE.Group, L: Layout): void {
  for (const t of L.toilets) {
    const [x, z] = cellCenter(t);
    g.add(box(0.42, 0.4, 0.5, P.porcelain, x, 0, z - 0.02));
    g.add(box(0.46, 0.55, 0.2, P.porcelain, x, 0.25, z - 0.35));
  }
  const d = L.toiletDivider;
  const dx = (d.x + 0.5) * CELL;
  g.add(box(0.06, 1.5, d.d * CELL, P.stall, dx, 0, d.z * CELL + d.d * CELL / 2));
  g.add(box(0.6, 0.4, 0.04, P.toiletSign, dx, 0.9, 0.03));
}

function buildGym(g: THREE.Group, L: Layout): void {
  for (const t of L.treadmills) {
    const [x, z] = cellCenter(t);
    g.add(box(0.62, 0.06, 1.3, P.treadmill, x, 0, z + 0.15));
    for (const ox of [-0.28, 0.28]) g.add(box(0.06, 1.0, 0.06, P.treadmill, x + ox, 0, z - 0.45));
    g.add(box(0.62, 0.22, 0.12, P.treadmillPanel, x, 1.0, z - 0.45));
  }
  for (const m of L.gymMats) {
    const [x, z] = cellCenter(m);
    g.add(flat(box(0.55, 0.03, 1.05, P.mat, x, 0, z)));
  }
  const [gx] = rectCenter(L.zones.gym);
  g.add(box(1.4, 0.45, 0.3, P.treadmill, gx + 1.6, 0, 0.2));
  for (let i = 0; i < 4; i++) g.add(box(0.12, 0.12, 0.25, P.dumbbell, gx + 1.1 + i * 0.33, 0.45, 0.2));
}

/** 一块木牌，上面写字；底边在 (x, y, z)，往后仰着对着相机。字多了牌子跟着变宽 */
function addSign(g: THREE.Group, text: string, x: number, y: number, z: number): { material: THREE.Material; texture: THREE.Texture } {
  const font = '700 104px -apple-system, "PingFang SC", sans-serif';
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d')!;
  ctx.font = font;
  canvas.width = Math.max(512, Math.ceil(ctx.measureText(text).width) + 120);
  canvas.height = 160;
  // 改了画布尺寸，字体要重新设
  ctx.font = font;
  ctx.fillStyle = P.signBoard;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = P.signText;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, canvas.width / 2, canvas.height / 2 + 6);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  const material = new THREE.MeshBasicMaterial({ map: texture });
  const width = 1.6 * canvas.width / 512;
  const sign = new THREE.Group();
  sign.position.set(x, y, z);
  sign.rotation.x = -BOARD_TILT;
  sign.add(box(width + 0.12, 0.58, 0.04, P.door, 0, 0, -0.02));
  const face = new THREE.Mesh(unitPlane, material);
  face.scale.set(width, 0.5, 1);
  face.position.set(0, 0.29, 0.005);
  sign.add(face);
  g.add(sign);
  return { material, texture };
}

/** 休闲区：一排游戏机、电视、懒人沙发 */
function buildLeisure(g: THREE.Group, L: Layout): void {
  const { arcades, tv, spots } = L.leisure;
  arcades.forEach((a, i) => {
    const [x, z] = rectCenter(a);
    const light = P.arcadeLights[i % P.arcadeLights.length];
    g.add(box(0.62, 1.55, 0.6, P.arcadeBody, x, 0, z - 0.15));
    g.add(box(0.66, 0.2, 0.14, light, x, 1.55, z - 0.05));
    g.add(box(0.66, 0.1, 0.34, P.arcadeBody, x, 0.88, z + 0.28));
    g.add(box(0.05, 0.12, 0.05, P.chairBase, x - 0.15, 0.98, z + 0.3));
    for (const ox of [0.05, 0.15, 0.25]) g.add(box(0.06, 0.03, 0.06, light, x + ox, 0.98, z + 0.3));
    const screen = new THREE.Mesh(unitPlane, glow(light));
    screen.scale.set(0.46, 0.34, 1);
    screen.position.set(x, 1.22, z + 0.16);
    screen.rotation.x = -0.25;
    g.add(screen);
  });

  const [tx, tz] = rectCenter(tv);
  g.add(box(tv.w * CELL - 0.2, 0.45, 0.4, P.tvStand, tx, 0, tz));
  g.add(box(2.0, 1.15, 0.08, P.monitor, tx, 0.5, tz - 0.08));
  const tvScreen = new THREE.Mesh(unitPlane, glow(P.tvScreen));
  tvScreen.scale.set(1.86, 1.0, 1);
  tvScreen.position.set(tx, 1.075, tz - 0.035);
  g.add(tvScreen);

  const bags = spots.filter(s => s.kind === 'beanbag');
  if (bags.length > 0) {
    const xs = bags.map(b => cellCenter(b)[0]), zs = bags.map(b => cellCenter(b)[1]);
    const x0 = Math.min(...xs) - 0.8, x1 = Math.max(...xs) + 0.8;
    const z0 = Math.min(...zs) - 0.6, z1 = Math.max(...zs) + 0.7;
    g.add(flat(box(x1 - x0, 0.012, z1 - z0, P.leisureRug, (x0 + x1) / 2, 0, (z0 + z1) / 2)));
  }
  bags.forEach((b, i) => {
    const [x, z] = cellCenter(b);
    const color = P.beanbags[i % P.beanbags.length];
    // 坐的人面朝北，靠背在南边
    g.add(box(0.78, 0.26, 0.74, color, x, 0, z));
    g.add(box(0.78, 0.42, 0.26, color, x, 0.12, z + 0.3));
  });
}

function buildPantry(g: THREE.Group, L: Layout): void {
  const c = L.pantryCounter;
  const [cx, cz] = rectCenter(c);
  g.add(box(c.w * CELL, 0.9, c.d * CELL, P.counter, cx, 0, cz));
  g.add(box(c.w * CELL + 0.06, 0.05, c.d * CELL + 0.06, P.counterTop, cx, 0.9, cz));
  P.snacks.forEach((color, i) => g.add(box(0.16, 0.22, 0.16, color, c.x * CELL + 0.3 + i * 0.45, 0.95, cz)));
  g.add(box(0.3, 0.4, 0.3, P.coffeeMachine, (c.x + c.w) * CELL - 0.3, 0.95, cz));
  const [fx, fz] = rectCenter(L.fridge);
  g.add(box(0.5, 1.8, 0.9, P.fridge, fx, 0, fz));
}
