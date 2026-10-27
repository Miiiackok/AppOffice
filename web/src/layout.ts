// 办公室平面布局。全部是格子坐标（0.5 米一格），x 向右、z 朝镜头；渲染时乘 CELL 变成米

export const CELL = 0.5;
/** 洗手间、健身房、茶水间固定占 28 列，右边剩下的都是休闲区 */
export const FACILITY_COLS = 28;
/** 休闲区至少这么宽，办公室不能比设施带加它窄 */
export const MIN_LEISURE_COLS = 22;
export const MIN_COLS = FACILITY_COLS + MIN_LEISURE_COLS;
export const CUBICLE = 6;
export const ROW_PITCH = 9;
export const FACILITY_ROWS = 8;
export const CORRIDOR_ROWS = 3;
/** 最后一排工位下面再留几行给大门 */
export const BOTTOM_ROWS = 3;
/** 大办公室：一人一间，玻璃墙围起来 */
export const OFFICE_W = 14;
export const OFFICE_D = 9;
/** 合用的小办公室：每张桌子占 4 列 5 行（桌子 3×2、椅子一行、过道两行，过道窄了地上的图标会被后一排桌子挡住），两排 */
export const DESK_UNIT_W = 4;
export const DESK_UNIT_D = 5;
export const SHARED_DESK_ROWS = 2;
export const SHARED_D = 2 + SHARED_DESK_ROWS * DESK_UNIT_D;
/** 房间之间、房间和外墙之间留的列 */
const ROOM_GAP = 1;
const MARGIN = 2;
const DOOR_W = 2;
const MIN_PER_ROW = 4;
/** 一排房间最多这么宽（4 间大办公室正好一排），再多就换到下一排 */
export const ROW_LIMIT = 59;
/** 第一排房间的上沿：设施带下面隔一条走道 */
export const ROOMS_TOP = FACILITY_ROWS + CORRIDOR_ROWS;

/** 面朝 -z（朝桌子、朝里） */
export const NORTH = Math.PI;
/** 面朝 +z（朝镜头） */
export const SOUTH = 0;

export interface Cell { x: number; z: number }
export interface Spot extends Cell { facing: number }
export interface Rect { x: number; z: number; w: number; d: number }

export interface Desk {
  desk: Rect;
  seat: Spot;
}

export interface Cubicle extends Desk {
  rect: Rect;
}

/** 休闲区里能待的地方：游戏机前站着打、懒人沙发上看电视、站在后面看人打游戏 */
export type LeisureKind = 'arcade' | 'beanbag' | 'watch';
export interface LeisureSpot extends Spot { kind: LeisureKind }

export interface Leisure {
  spots: LeisureSpot[];
  /** 游戏机，靠北墙 */
  arcades: Rect[];
  /** 电视柜，靠北墙 */
  tv: Rect;
}

/** 玻璃墙围起来的房间；rect 含墙，门开在南墙上 */
export interface Room {
  rect: Rect;
  door: { x: number; w: number };
  desks: Desk[];
}

export interface Office extends Room {
  sofa: Rect;
  shelf: Rect;
}

/** 合用的小办公室，门口挂着名字 */
export interface SharedRoom extends Room {
  name: string;
}

/** 布局要知道的：几间大办公室、每间小办公室叫什么坐几个人、几个临时工隔间 */
export interface LayoutSpec {
  offices: number;
  rooms: { name: string; desks: number }[];
  temp: number;
}

export interface Layout {
  cols: number;
  rows: number;
  spec: LayoutSpec;
  /** cols × rows，1 = 能走 */
  walkable: Uint8Array;
  offices: Office[];
  /** 和 spec.rooms 一一对应；没人的房间不盖（desks 为空） */
  rooms: SharedRoom[];
  /** 临时工的独立隔间，一人一个，在所有房间下面 */
  cubicles: Cubicle[];
  cubicleTop: number;
  perRow: number;
  cubicleRows: number;
  toiletDivider: Rect;
  toilets: Spot[];
  toiletQueue: Spot[];
  treadmills: Spot[];
  gymMats: Spot[];
  pantryCounter: Rect;
  fridge: Rect;
  pantry: Spot[];
  pantryQueue: Spot[];
  leisure: Leisure;
  door: Spot;
  zones: { toilet: Rect; gym: Rect; pantry: Rect; leisure: Rect; open: Rect };
}

export const EMPTY_SPEC: LayoutSpec = { offices: 0, rooms: [], temp: 0 };

const spot = (x: number, z: number, facing: number): Spot => ({ x, z, facing });
const sharedPerRow = (n: number) => Math.ceil(n / SHARED_DESK_ROWS);
const sharedWidth = (n: number) => (n === 0 ? 0 : 3 + sharedPerRow(n) * DESK_UNIT_W);
/** 一排房间的总宽（含房间之间的空） */
const rowWidth = (widths: number[]) => widths.reduce((a, b) => a + b, 0) + Math.max(0, widths.length - 1) * ROOM_GAP;

/** 按顺序往一排里放，放不下就换下一排；返回每排放了哪几个（下标） */
function packRows(widths: number[]): number[][] {
  const limit = Math.max(ROW_LIMIT, ...widths);
  const rows: number[][] = [];
  let current: number[] = [];
  widths.forEach((w, i) => {
    if (w === 0) return;
    if (current.length > 0 && rowWidth([...current.map(j => widths[j]), w]) > limit) {
      rows.push(current);
      current = [];
    }
    current.push(i);
  });
  if (current.length > 0) rows.push(current);
  return rows;
}

export function sameSpec(a: LayoutSpec, b: LayoutSpec): boolean {
  return a.offices === b.offices && a.temp === b.temp && a.rooms.length === b.rooms.length
    && a.rooms.every((r, i) => r.name === b.rooms[i].name && r.desks === b.rooms[i].desks);
}

/** 所有员工会去的位置，包括大门 */
export function spotsOf(L: Layout): Spot[] {
  return [
    ...L.offices.map(o => o.desks[0].seat), ...L.rooms.flatMap(r => r.desks.map(d => d.seat)),
    ...L.cubicles.map(c => c.seat), ...L.toilets, ...L.toiletQueue,
    ...L.treadmills, ...L.gymMats, ...L.pantry, ...L.pantryQueue, ...L.leisure.spots, L.door,
  ];
}

export function computeLayout(spec: LayoutSpec): Layout {
  const officeWidths = Array.from({ length: spec.offices }, () => OFFICE_W);
  const roomWidths = spec.rooms.map(r => sharedWidth(r.desks));
  const officeRows = packRows(officeWidths);
  const roomRows = packRows(roomWidths);
  const widest = Math.max(0, ...[...officeRows.map(r => r.map(i => officeWidths[i])),
    ...roomRows.map(r => r.map(i => roomWidths[i]))].map(rowWidth));
  const cols = Math.max(MIN_COLS, 2 * MARGIN + widest, 5 + MIN_PER_ROW * CUBICLE);
  const cubicleTop = ROOMS_TOP + officeRows.length * (OFFICE_D + CORRIDOR_ROWS) + roomRows.length * (SHARED_D + CORRIDOR_ROWS);
  const perRow = Math.floor((cols - 5) / CUBICLE);
  const cubicleRows = Math.max(1, Math.ceil(spec.temp / perRow));
  const rows = cubicleTop + cubicleRows * ROW_PITCH + BOTTOM_ROWS;
  const walkable = new Uint8Array(cols * rows).fill(1);
  const block = (r: Rect) => {
    for (let z = r.z; z < r.z + r.d; z++)
      for (let x = r.x; x < r.x + r.w; x++)
        if (x >= 0 && x < cols && z >= 0 && z < rows) walkable[z * cols + x] = 0;
  };
  /** 玻璃墙挡路，南墙留门 */
  const walls = (rect: Rect, door: { x: number; w: number }) => {
    const south = rect.z + rect.d - 1;
    block({ x: rect.x, z: rect.z, w: rect.w, d: 1 });
    block({ x: rect.x, z: rect.z, w: 1, d: rect.d });
    block({ x: rect.x + rect.w - 1, z: rect.z, w: 1, d: rect.d });
    block({ x: rect.x, z: south, w: door.x - rect.x, d: 1 });
    block({ x: door.x + door.w, z: south, w: rect.x + rect.w - door.x - door.w, d: 1 });
  };
  const doorOf = (rect: Rect) => ({ x: rect.x + Math.floor(rect.w / 2) - 1, w: DOOR_W });
  /** 每排在办公室里居中，返回这排每个房间的左边列 */
  const lefts = (row: number[], widths: number[]) => {
    let x = Math.floor((cols - rowWidth(row.map(i => widths[i]))) / 2);
    return row.map(i => {
      const left = x;
      x += widths[i] + ROOM_GAP;
      return left;
    });
  };
  let top = ROOMS_TOP;

  // 大办公室：大桌子靠北墙居中，右边沙发，左边书架
  const offices: Office[] = [];
  for (const row of officeRows) {
    for (const x of lefts(row, officeWidths)) {
      const rect = { x, z: top, w: OFFICE_W, d: OFFICE_D };
      const door = doorOf(rect);
      const desk = { x: x + 4, z: top + 2, w: 5, d: 2 };
      const sofa = { x: x + OFFICE_W - 3, z: top + 2, w: 2, d: 4 };
      const shelf = { x: x + 1, z: top + 1, w: 1, d: 3 };
      walls(rect, door);
      block(desk);
      block(sofa);
      block(shelf);
      offices.push({ rect, door, desks: [{ desk, seat: spot(x + 6, top + 4, NORTH) }], sofa, shelf });
    }
    top += OFFICE_D + CORRIDOR_ROWS;
  }

  // 合用的小办公室：一人一张小桌子一台电脑，没有挡板，两排桌子
  const rooms: SharedRoom[] = spec.rooms.map(r => ({ name: r.name, rect: { x: 0, z: 0, w: 0, d: 0 }, door: { x: 0, w: 0 }, desks: [] }));
  for (const row of roomRows) {
    lefts(row, roomWidths).forEach((x, k) => {
      const i = row[k];
      const n = spec.rooms[i].desks;
      const rect = { x, z: top, w: roomWidths[i], d: SHARED_D };
      const door = doorOf(rect);
      const desks: Desk[] = [];
      for (let j = 0; j < n; j++) {
        const ux = x + 2 + (j % sharedPerRow(n)) * DESK_UNIT_W;
        const uz = top + 1 + Math.floor(j / sharedPerRow(n)) * DESK_UNIT_D;
        const desk = { x: ux, z: uz, w: 3, d: 2 };
        block(desk);
        desks.push({ desk, seat: spot(ux + 1, uz + 2, NORTH) });
      }
      walls(rect, door);
      rooms[i] = { name: spec.rooms[i].name, rect, door, desks };
    });
    top += SHARED_D + CORRIDOR_ROWS;
  }

  // 临时工：一人一个隔间（后挡板、左挡板、桌子挡路，开口朝走道），开了几个就有几个
  const cubicleX = Math.floor((cols - perRow * CUBICLE - 1) / 2);
  const cubicles: Cubicle[] = [];
  for (let i = 0; i < spec.temp; i++) {
    const cx = cubicleX + (i % perRow) * CUBICLE;
    const cz = cubicleTop + Math.floor(i / perRow) * ROW_PITCH;
    const desk = { x: cx + 1, z: cz + 1, w: 5, d: 2 };
    block({ x: cx, z: cz, w: CUBICLE, d: 1 });
    block({ x: cx, z: cz, w: 1, d: CUBICLE });
    block(desk);
    // 每排最后一个隔间右边封上
    if (i % perRow === perRow - 1 || i === spec.temp - 1) block({ x: cx + CUBICLE, z: cz, w: 1, d: CUBICLE });
    cubicles.push({ rect: { x: cx, z: cz, w: CUBICLE, d: CUBICLE }, desk, seat: spot(cx + 3, cz + 3, NORTH) });
  }

  // 设施带：洗手间、健身房、茶水间各占固定宽度，右边剩下的都给休闲区
  // 洗手间：两个坑位，中间隔板，排队的人站在外面
  const toiletDivider = { x: 4, z: 0, w: 1, d: 4 };
  block({ x: 2, z: 1, w: 1, d: 1 });
  block({ x: 6, z: 1, w: 1, d: 1 });
  block(toiletDivider);
  const toilets = [spot(2, 2, SOUTH), spot(6, 2, SOUTH)];
  const toiletQueue = [spot(4, 5, NORTH), spot(4, 6, NORTH), spot(3, 6, NORTH), spot(2, 6, NORTH), spot(1, 6, NORTH)];

  // 健身房：三台跑步机，满了去垫子上做俯卧撑
  for (const x of [11, 14, 17]) block({ x, z: 1, w: 1, d: 1 });
  const treadmills = [11, 14, 17].map(x => spot(x, 2, NORTH));
  const gymMats = [10, 12, 14, 16, 18].map(x => spot(x, 5, SOUTH));

  // 茶水间：吧台四个位置，满了在后面等
  const pantryCounter = { x: 20, z: 1, w: 7, d: 1 };
  const fridge = { x: 27, z: 0, w: 1, d: 2 };
  block(pantryCounter);
  block(fridge);
  const pantry = [20, 22, 24, 26].map(x => spot(x, 2, NORTH));
  const pantryQueue = [spot(21, 5, NORTH), spot(23, 5, NORTH), spot(25, 5, NORTH), spot(22, 6, NORTH), spot(24, 6, NORTH)];

  // 休闲区：左边一排游戏机，右边电视对着几排懒人沙发
  const lx = FACILITY_COLS, lw = cols - FACILITY_COLS;
  const arcades: Rect[] = [];
  const spots: LeisureSpot[] = [];
  const arcadeCount = Math.max(2, Math.min(4, Math.floor((lw - 10) / 3)));
  for (let i = 0; i < arcadeCount; i++) {
    const x = lx + 2 + i * 3;
    arcades.push({ x, z: 0, w: 1, d: 2 });
    block({ x, z: 0, w: 1, d: 2 });
    spots.push({ ...spot(x, 2, NORTH), kind: 'arcade' });
  }
  for (let i = 0; i < arcadeCount - 1; i++) spots.push({ ...spot(lx + 3 + i * 3, 4, NORTH), kind: 'watch' });
  const loungeX = lx + 2 + arcadeCount * 3 + 1;
  const loungeW = lx + lw - 1 - loungeX;
  const bagsPerRow = Math.max(1, Math.floor((loungeW + 1) / 3));
  const bagsSpan = bagsPerRow * 3 - 2;
  const firstBag = loungeX + Math.floor((loungeW - bagsSpan) / 2);
  const tv = { x: firstBag + Math.floor(bagsSpan / 2) - 2, z: 0, w: 5, d: 1 };
  block(tv);
  for (const z of [3, 5]) {
    for (let i = 0; i < bagsPerRow; i++) spots.push({ ...spot(firstBag + i * 3, z, NORTH), kind: 'beanbag' });
  }
  const leisure = { spots, arcades, tv };

  const door = spot(cols - 4, rows - 1, SOUTH);
  const openTop = cubicleTop - 2;

  return {
    cols, rows, spec, walkable, offices, rooms, cubicles, cubicleTop, perRow, cubicleRows,
    toiletDivider, toilets, toiletQueue, treadmills, gymMats,
    pantryCounter, fridge, pantry, pantryQueue, leisure, door,
    zones: {
      toilet: { x: 0, z: 0, w: 9, d: FACILITY_ROWS },
      gym: { x: 9, z: 0, w: 10, d: FACILITY_ROWS },
      pantry: { x: 19, z: 0, w: 9, d: FACILITY_ROWS },
      leisure: { x: lx, z: 0, w: lw, d: FACILITY_ROWS },
      open: { x: 0, z: openTop, w: cols, d: rows - openTop },
    },
  };
}
