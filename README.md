# AppOffice · 摸鱼办公室

一个 macOS 菜单栏小工具：把电脑里的 app 当成员工，放进一个 3D 小办公室。没打开的 app 在工位上摸鱼，正在用的疯狂干活，卡住的去上厕所，断网时联网的 app 去健身房，内存吃太多的去茶水间吃零食。

## 安装

需要 macOS 14+、Xcode（Swift 5.9+）和 Node 22。

```bash
git clone https://github.com/MiWang0608/AppOffice.git
cd AppOffice
scripts/build-app.sh --install
```

装好后在「应用程序」（`~/Applications`）里双击 **AppOffice**。它只在菜单栏出现（一个小楼图标），没有 Dock 图标。

## 怎么玩

**员工是谁**：名单写在 `Sources/OfficeCore/Roster.swift`（`Roster.rooms`），装了就有座位，和 Dock 里有没有无关；打开、干活都在自己的座位上。地毯颜色是图标主色，看板挂着图标。想换成自己的名单：改 `Roster.rooms` 再跑一次 `scripts/build-app.sh --install`。

| 房间 | 谁 |
|---|---|
| 大办公室（一人一间，玻璃墙） | Google Chrome、Claude、ChatGPT、WeChat |
| 小办公室 · 12 人（一人一张桌子） | 电话、日历、通讯录、备忘录、提醒事项、TV、音乐、照片、FaceTime、信息、邮件、游戏 |
| 小办公室 · 7 人 | Keynote、Numbers、Pages、App Store、iPhone 镜像、Siri、系统设置 |
| 小办公室 · Dock | 访达、启动台、Safari、地图，以及 Dock 里其他不在名单上的 app |
| 下面的独立隔间 | 临时工：其他打开的 app，从大门走进来，一人一个隔间，开几个就有几个 |

| 员工在干嘛 | 说明 app 在 |
|---|---|
| 🚽 去洗手间（满了门口排队） | 卡住了（转彩球） |
| 🏋️ 去健身房 | 电脑断网，而且这个 app 最近联过网 |
| 🎒 背包端咖啡 | 正在启动 |
| ⌨️ 疯狂打字（CPU 越高越快，冒汗） | 你正在用 |
| 🍪 去茶水间 | 后台占了 2 GB 以上内存 |
| 💻 打字 | 后台在干活：整个 app（含 Helper 和它启动的子进程）最近 5 秒平均 CPU 超过 12%，之后保持 30 秒（AI 等回复时也算） |
| ☕ 喝咖啡 | 开着但闲着 |
| 😴 睡觉 / 刷手机 / 转椅子 / 伸懒腰 | 没打开 |
| 🎮 去休闲区打游戏机、窝懒人沙发看电视、围观（隔几秒有人换个地方） | 没打开，而且 7 天没用过（按 macOS 记的上次使用时间；从没用过也算）。一打开就回座位 |

**操作**

| 操作 | 效果 |
|---|---|
| 单击小人 | 名片：状态、CPU、内存、开了多久 |
| 双击小人或他的座位 | 没打开就启动，开着就切过去 |
| 把小人拖到右下角大门 | 退出这个 app（和 ⌘Q 一样，没保存的文档 app 会自己问你） |
| 拖空白处 / 滚轮 / 双击空白处 | 转视角（±30°）/ 缩放 / 复位 |

**菜单栏**：显示办公室、钉在最上层、透明模式（鼠标不在窗上时半透明）、开启卡顿检测…、调试 → 模拟状态、退出。

## 权限

- **辅助功能**（卡顿检测要用）：菜单里点「开启卡顿检测…」，在系统设置里打开 AppOffice。没开的话其他功能照常，只是没人去洗手间。
- 脚本用的是临时签名（ad-hoc），每次重新打包后系统会认为这是一个新的程序，辅助功能里的开关看着是开的，其实已经失效了。需要在 系统设置 → 隐私与安全性 → 辅助功能 里把 AppOffice 删掉（−）再重新加上（或者关掉再打开）。
- 用 `swift run` 开发时，权限给的是运行它的终端。

## 注意

- 打包的 app 和 `swift run` 的设置（钉住、透明、窗口位置）是分开存的，第一次打开 app 会是默认设置。
- 浮窗不抢焦点，所以按 Esc 关不了名片，点一下空白处就行。

## 开发

```bash
npm --prefix web run build      # 先打包网页
swift run AppOffice             # 运行（会用仓库里的 web/dist）
APP_OFFICE_LOG=1 swift run AppOffice   # 打印和网页之间的消息
swift run officectl             # 终端里看状态，不开窗口
swift test                      # Swift 测试
npm --prefix web test           # 网页测试
```

- 只调网页：`cd web && npm run dev`，浏览器打开 `http://localhost:5173/`（假数据）。详见 `web/README.md`。
- 调试运行中的网页：Safari →「开发」菜单 → 找到 AppOffice。
- `APP_OFFICE_WEB=/path/to/dist` 可以指定网页资源目录。

设计文档和实现计划在 `docs/superpowers/`。

## 许可证

[MIT](LICENSE)
