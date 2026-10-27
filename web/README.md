# AppOffice 网页场景

3D 办公室：每个 app 是一个员工。Swift 外壳通过 `window.office.receive(msg)` 推送名单和状态，网页通过 `webkit.messageHandlers.office.postMessage(action)` 发回操作。消息格式见 `src/protocol.ts` 和设计文档 5.3。

## 开发

```bash
npm install
npm run dev
```

| 地址 | 内容 |
|---|---|
| `http://localhost:5173/` | 完整办公室，用假数据（左上角按钮：断网、卡住一个、来/走临时工……） |
| `?gallery` | 所有动作排成一排 |
| `?layout=12` | 房间坐满、12 个临时工时的空办公室 |

浏览器控制台里可以直接用 `mock`，例如 `mock.set('mock.mail', 'hung')`。
mock 模式下还有 `app`（OfficeApp），可以手动推进动画，例如 `app.frame(1 / 30, performance.now() / 1000)`。

## 检查

```bash
npm test
npm run typecheck
npm run build
```

打包结果在 `dist/`，资源路径都是相对路径（`./assets/...`），由 Swift 外壳从 app 包里加载。
