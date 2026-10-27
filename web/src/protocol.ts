// 与 Swift 外壳之间的消息格式（设计文档 5.3）
export type EmployeeState =
  | 'hung' | 'offline' | 'launching' | 'focused' | 'snacking' | 'working' | 'idle' | 'resting' | 'off';
export type EmployeeKind = 'staff' | 'temp';
/** 房间（来自 rooms.json）：offices 是一排大办公室、每人一间；shared 是合用的小办公室，name 挂在门口 */
export interface RoomInfo {
  name: string;
  kind: 'offices' | 'shared';
}
export type NetworkState = 'online' | 'offline';

export interface RosterEmployee {
  id: string;
  name: string;
  kind: EmployeeKind;
  /** 正式员工的房间（roster 消息里 rooms 的下标）；临时工为 null */
  room: number | null;
  /** 正式员工在房间里的座位序号（大办公室里是第几间）；临时工为 null */
  seat: number | null;
  /** 图标主色 #RRGGBB */
  color: string;
  /** 64×64 PNG 的 base64，不带 data: 前缀 */
  iconPNG: string;
}

export interface EmployeeStatus {
  id: string;
  state: EmployeeState;
  cpu: number;
  memMB: number;
  /** Unix 秒；没运行为 null */
  launchedAt: number | null;
}

export type InboundMessage =
  | { type: 'roster'; rooms: RoomInfo[]; employees: RosterEmployee[] }
  | { type: 'status'; network: NetworkState; employees: EmployeeStatus[] }
  | { type: 'paused'; paused: boolean }
  | { type: 'locale'; lang: 'zh' | 'en' };

export type OutboundAction =
  | { action: 'activate' | 'launch' | 'quit'; id: string }
  | { action: 'ready' };
