# AppOffice · 摸鱼办公室 设计文档

日期：2026-10-14

## 1. 概述

一个 macOS 小工具：把电脑里的 app 当成员工，放进一个 3D 小办公室。没打开的 app 在工位上摸鱼，正在用的 app 疯狂干活，卡住的 app 去上厕所，断网时联网 app 去健身房。

- 形态：菜单栏常驻图标 + 可显示/隐藏/置顶的浮动小窗（默认约 360×260，可拖动、可缩放）。
- 画风：低多边形办公室 + 体素（方块）小人，配色参考 https://www.cubicles.lol/ （奶油白墙、浅木桌、浅灰隔板、绿植、彩色描边地毯、墙上看板）。
- 互动：可当启动器用——点工位启动/切换 app，点小人看名片，拖小人到大门"开除"（正常退出）。
- 平台：macOS 14+，不进沙盒（需要辅助功能权限与读取其他进程信息），无 Dock 图标。

## 2. 员工

### 2.1 名单

| 类型 | 来源 | 工位 |
|---|---|---|
| 正式员工 | 房间名单 `rooms.json` 里装了的 app，加上 Dock 中固定的其他 app（读 `com.apple.dock` 的 `persistent-apps`，坐进标了 `"dock": true` 的房间） | 按房间坐，见下 |
| 临时工 | 正在运行、`activationPolicy == .regular`、但不在名单也不在 Dock 固定列表里的 app | 一人一个独立隔间，开几个建几个 |

> 2026-10-25 改版：原来正式员工按 Dock 顺序坐隔间、临时工坐开放长桌和沙发，结果在干活的 app 坐长桌、没开的反而占隔间。现在改成按房间：
>
> | 房间 `room` | 谁 | 样子 |
> |---|---|---|
> | `office` | Google Chrome、Claude、ChatGPT（`com.openai.chat` 或 `com.openai.codex`）、WeChat | 一人一间大办公室：玻璃墙、两台显示器的大桌子、墙上大看板、书架、沙发 |
> | `apple` | 电话、日历、通讯录、备忘录、提醒事项、TV、音乐、照片、FaceTime、信息、邮件、游戏 | 合用小办公室，一人一张小桌子一台电脑，没有挡板 |
> | `tools` | Keynote、Numbers、Pages、App Store、iPhone 镜像、Siri、系统设置 | 同上 |
> | `dock` | 访达、启动台、Safari、地图，然后是 Dock 里其他不在名单上的 app | 同上，人多了房间变宽 |
>
> 名单上的 app 没在 Dock 里、也没运行时，用 LaunchServices 找它装在哪（每 10 秒一次）；没装就跳过。不管开没开、在不在干活，都坐自己的座位。
>
> 2026-10-27 改：名单搬到 `~/Library/Application Support/AppOffice/rooms.json`（README 有写法），房间数量和名字都能改：`offices` 一排大办公室（4 间一排，多了换行），`rooms` 一间间小办公室（一排放不下 59 列就换行，名字挂在北墙玻璃顶上）。app 写名字或 bundle id，按 Dock → 运行中 → 已安装（扫应用程序文件夹，一分钟一次）的顺序对。没有文件就按 Dock 生成；每秒看一眼修改时间，改了马上重排；写坏了弹通知、沿用上一版。roster 消息多一个 `rooms` 数组，员工的 `room` 是它的下标。

- Dock 固定列表变化时重新排座（每 10 秒检查一次）。
- 每个员工的 `id` 是 bundle identifier。
- 身份标识：衬衫颜色、隔间地毯描边色 = app 图标主色；隔间看板挂 app 图标；小人头顶悬浮一个小图标牌（billboard）。
- 主色提取：把图标缩到 32×32，忽略透明和近白/近黑像素，取饱和度加权后出现最多的色相桶的平均色；没有合适像素时用中性灰 `#9AA5B1`。

### 2.2 状态（按优先级，从高到低，取第一个成立的）

| 优先级 | 状态 `state` | 条件 | 行为 |
|---|---|---|---|
| 1 | `hung` | app 在运行，且卡顿检测连续 2 次超时 | 走去洗手间，门挂"有人"；恢复后洗手回工位 |
| 2 | `offline` | 整机网络不可用，且该 app 在最近 10 分钟内有过网络流量 | 去健身房跑步机跑步；网络恢复后回来 |
| 3 | `launching` | app 在运行，`isFinishedLaunching == false` | 背包端咖啡从大门走进来，坐下开电脑 |
| 4 | `focused` | app 是当前前台 app | 疯狂打字，速度与 CPU 挂钩；CPU ≥ 80% 头上冒汗、纸片乱飞 |
| 5 | `snacking` | 后台运行，内存占用（phys_footprint）≥ 2 GB | 去茶水间吃零食 |
| 6 | `working` | 后台运行，最近 5 秒平均 CPU ≥ 12%（整个进程家族），或者 30 秒内满足过 | 在工位干活，比 `focused` 慢 |
| 7 | `idle` | 后台运行，其他情况 | 工位上半摸鱼：喝咖啡、看屏幕 |
| 8 | `resting` | 未运行，且 7 天没用过（Spotlight 的 `kMDItemLastUsedDate` 和 AppOffice 最后一次看到它开着，取晚的；都没有算从没用过） | 去休闲区自由活动：游戏机前打游戏、懒人沙发上看电视、站后面围观；每 4 秒随机一个人换个空位 |
| 9 | `off` | 未运行（只有正式员工会处于此状态） | 摸鱼动画轮播：趴桌睡觉 zzz、刷手机、转椅子、伸懒腰 |

- CPU 为最近 1 秒采样窗口内该 app 整个进程家族（主进程 + `responsibility_get_pid_responsible_for_pid` 指向它的所有进程：Electron Helper、浏览器渲染进程、它启动的命令行工具）占单核的百分比之和（可超过 100，展示时封顶 100）。内存仍只算主进程。
- 2026-10-27 改：原来只看主进程、门槛 20%，在后台跑任务的 Claude 主进程只有 1–2%（全家 10–60%），切走就变半摸鱼。实测闲着的 ChatGPT 全家 5–9%，所以门槛定 12%、取 5 秒平均；AI 等服务器回复时几乎不用 CPU，所以过线后保持 30 秒。前台时也在记，切走时如果刚在干活就直接接着干。
- 临时工在 app 退出后：背包走出大门，然后从名单移除。
- 正式员工在 app 退出后：回到自己工位进入 `off`。

### 2.3 设施与排队

| 设施 | 容量 | 超出时 |
|---|---|---|
| 洗手间 | 2 个坑位 | 门口排队，原地跺脚 |
| 健身房 | 3 台跑步机 | 在垫子上做俯卧撑 |
| 茶水间 | 4 个位置 | 站在旁边等着吃 |
| 休闲区 | 4 台游戏机 + 3 个围观位 + 懒人沙发（随宽度，通常 12 个） | 满了挤在最后一个位置 |

### 2.4 不做（第一版）

- 单个 app"在等网络"的检测（只能靠猜，易误判）。只做整机断网。
- 区分崩溃与正常退出。

## 3. 办公室与画面

### 3.1 平面布局

```
┌──────────────────────────────────────────┐
│ 洗手间 │ 健身房 │ 茶水间 │    休闲区     │
├──────────────────────────────────────────┤
│ [Chrome] [Claude] [ChatGPT] [WeChat] 大办公室│
│  ────────── 走道 ──────────              │
│ [ 12 人间 ]  [ 7 人间 ]  [ Dock 间 ]      │
│  ────────── 走道 ──────────              │
│ [隔间][隔间][隔间]…  ← 临时工，开几个建几个 │
│                                   大门   │
└──────────────────────────────────────────┘
```

- 顶上设施带：洗手间、健身房、茶水间各占固定宽度，右边剩下的全是休闲区；四个区的后墙顶上各挂一块写着名字的木牌。
- 房间都有玻璃墙，门开在南墙上。办公室宽度取大办公室那排和小办公室那排里宽的那个；临时工隔间一排放得下多少放多少，不够再加一排。
- 行走：粗粒度网格（0.5 m 一格）上的 A* 寻路，只走走道，不穿墙。

### 3.2 镜头与渲染

- 高角度透视俯视，默认视角自动缩放到能装下整个办公室。
- 滚轮缩放；按住拖动水平旋转，限制在默认视角 ±30°；双击空白处恢复默认视角。
- 所有几何体在代码中用方块（BoxGeometry）程序化拼出，不依赖外部模型文件。
- 小人共用一套体素模型（头、身体、两臂、两腿），只换衬衫颜色和头顶图标。
- 帧率：浮窗可见时 30 fps；窗口被完全遮挡（`occlusionState` 不含 `.visible`）、隐藏或屏幕锁定时停止渲染循环。

## 4. 互动

| 操作 | 结果 |
|---|---|
| 单击小人 | 弹出名片：名字、图标、状态、CPU、内存、已运行时长 |
| 双击小人，或双击他的座位 | 该 app 已运行则切到前台；未运行（`off`）则启动 |
| 把小人拖到大门 | 对该 app 发送正常退出请求（等同 ⌘Q；未保存文档由 app 自己弹窗处理） |
| 菜单栏图标 | 显示/隐藏浮窗、钉在最上层、透明模式（鼠标不在窗上时 50% 透明）、开启卡顿检测、调试 → 模拟状态、退出 |

浮窗是不抢焦点的 `NSPanel`（`.nonactivatingPanel`），所以点它不会改变"前台 app"的判定。

## 5. 技术方案

Swift 外壳 + WKWebView 内嵌 Three.js 场景。

### 5.1 目录

```
AppOffice/
├── Package.swift
├── Sources/OfficeCore/          纯逻辑，可单元测试
│   ├── Roster.swift              员工名单合并、图标、主色
│   ├── ActivitySampler.swift     每进程 CPU%（proc_pid_rusage 差分）与内存（phys_footprint）
│   ├── HangDetector.swift        AXUIElement 消息超时探测（0.5 s）
│   ├── NetworkWatcher.swift      NWPathMonitor + 每 30 s 用 nettop 记录哪些进程有流量
│   └── StateResolver.swift       采样快照 → 每个员工的状态（纯函数，实现 2.2 的优先级表）
├── Sources/AppOffice/           macOS 外壳
│   ├── main.swift / AppDelegate.swift
│   ├── MenuBarController.swift
│   ├── OfficePanel.swift         浮动小窗
│   ├── WebBridge.swift           Swift ↔ JS 消息
│   └── AppControl.swift          启动 / 激活 / 正常退出
├── Tests/OfficeCoreTests/
└── web/                         TypeScript + Three.js + Vite
    ├── src/scene/                程序化场景：隔间、设施、小人
    ├── src/agents/               员工动画状态机、寻路、设施排队
    ├── src/bridge.ts             接收 Swift 推送 / 发出操作请求
    └── src/mock.ts               浏览器开发用的假数据驱动
```

构建时 `web/` 用 Vite 打包到 `web/dist/`，再作为资源拷进 app，WKWebView 从本地文件加载，不联网。

### 5.2 数据流

```
每 1 秒：Roster + ActivitySampler + HangDetector + NetworkWatcher
        → StateResolver → [Employee]
        → WebBridge（只推送有变化的员工）→ JS 员工状态机切换动画 / 寻路

JS 点击/拖动 → WebBridge → AppControl
```

### 5.3 消息协议

Swift → JS（`window.office.receive(msg)`）：

```json
{ "type": "roster",
  "rooms": [{ "name": "大办公室", "kind": "offices" }, { "name": "Dock 部", "kind": "shared" }],
  "employees": [{ "id": "com.apple.Safari", "name": "Safari", "kind": "staff",
                  "room": 1, "seat": 2, "color": "#3D7BFD", "iconPNG": "<base64, 64×64>" }] }

{ "type": "status",
  "network": "online",
  "employees": [{ "id": "com.apple.Safari", "state": "focused",
                  "cpu": 42, "memMB": 812, "launchedAt": 1791900000 }] }
```

- `roster` 只在名单变化时发送（含图标）；`status` 每秒发送，只含有变化的员工。
- `launchedAt` 为 app 启动时间（Unix 秒，未运行时为 `null`），已运行时长由 JS 自行计算，避免每秒都算"有变化"。
- `rooms`：`[{ "name": "大办公室", "kind": "offices" }, { "name": "生活部", "kind": "shared" }, …]`，第 0 个总是大办公室那排。
- `kind`：`"staff"` 或 `"temp"`。`room`：正式员工的房间（`rooms` 的下标）；`seat`：在房间里的座位序号（大办公室里是第几间）。临时工两个都是 `null`，由 JS 分配隔间。

```json
{ "type": "paused", "paused": true }
```

- `paused`：窗口被完全遮挡、隐藏或锁屏时 Swift 发 `true`，网页停止渲染；恢复时发 `false`。

JS → Swift（`webkit.messageHandlers.office.postMessage`）：

```json
{ "action": "activate", "id": "com.apple.Safari" }
{ "action": "launch",   "id": "com.apple.Safari" }
{ "action": "quit",     "id": "com.apple.Safari" }
{ "action": "ready" }
```

JS 发 `ready` 后，Swift 推送一次完整的 `roster` 与 `status`。

## 6. 错误处理

| 情况 | 处理 |
|---|---|
| 未授予辅助功能权限 | 卡顿检测关闭（没人去洗手间）；菜单显示"开启卡顿检测…"，点击打开系统设置对应页面；其余功能正常 |
| nettop 不可用或解析失败 | 断网时所有运行中的 app 都视为联网 app |
| 启动 app 失败 | 小人耸肩动画 + 系统通知 |
| 网页资源加载失败 | 窗口内显示一行文字提示 |
| 进程信息读取失败（权限/已退出） | 该员工 CPU、内存记为 0，不影响其他员工 |

## 7. 测试

- `OfficeCoreTests`：
  - `StateResolver` 表格驱动测试，覆盖 2.2 每一行及多条件同时成立时的优先级。
  - `Roster` 合并：Dock 固定 + 运行中 → 正式/临时划分；非 regular app 被排除。
  - 主色提取：纯色图、透明图、黑白图。
- `web/`：vitest 测 A* 寻路与设施排队分配。
- 手动：`npm run dev` + `mock.ts` 在浏览器中逐个检查动画；菜单"调试 → 模拟状态"在真实 app 里强制某员工进入指定状态。
