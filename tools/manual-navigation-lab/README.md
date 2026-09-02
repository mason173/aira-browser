# Aira 手动导航靶场

这是给手机真机手动点击用的本地网站，用来检查 Aira 浏览器处理复杂网站导航时是否稳定。
它不是自动化测试套件，也不会给 App 增加测试入口。

导航靶场和下载专项靶场已经合并到这一套服务器里。以后只启动这个服务器，不需要再分开跑两个本地服务。

## 启动

```bash
cd /path/to/aira-browser-harmonyos
node tools/manual-navigation-lab/server.js
```

如果端口被占用：

```bash
cd /path/to/aira-browser-harmonyos
PORT=8788 node tools/manual-navigation-lab/server.js
```

旧下载专项命令仍然可用，但它现在只是兼容入口，也会启动这套统一服务器：

```bash
cd /path/to/aira-browser-harmonyos
node scripts/start-download-test-server.js
```

启动后终端会打印 `127.0.0.1` 和局域网地址。手机和 Mac 在同一个网络下时，用手机上的 Aira 打开局域网地址，例如：

```text
http://192.168.x.x:8787/
```

常用入口：

- 默认人话模式：`/`
- 专家总览：`/expert`
- 普通下载靶场：`/downloads`
- 城通网盘保存复现页：`/download-fixture`

## 怎么判断成功

- 普通网页跳转、重定向、登录回调、支付回调：应该留在 Aira Web 内正常加载，地址栏、标题、进度、返回栈跟着真实页面变化。
- 新窗口和弹窗：`target=_blank`、`window.open`、`about:blank` 写入应该能打开可用的新页，目标 URL 不丢，OAuth 弹窗能把消息发回 opener。
- 外部 App / scheme：用户点击触发可以提示或尝试打开；自动触发、iframe 触发不应该静默劫持当前网页；失败后 fallback 应该能回到 Web。
- SPA 和回调清理：`pushState`、`replaceState`、hash 变化后，地址栏不应该被旧 URL 恢复；已经显示内容的 callback 清理参数后不应该倒退。
- 慢加载、流式加载、晚 title/favicon：进度不应卡死，标题和图标最终应更新到页面当前状态。
- 滚动、视觉采样、快照：滚动时工具栏/颜色/页面可见状态应该跟着变化，切标签回来不应该显示旧快照或错页。
- 下载和异常 MIME：附件下载、重定向下载、Blob 下载、JSON/PDF/text/plain HTML 应该按 Aira 当前策略处理，不应无限加载、重复下载或污染返回栈。
- 城通网盘保存复现页：点“模拟点击下载”后应出现“下载完成”弹层；点“保存到设备”后保存出来的文件不应是 0KB。

## 怎么记录问题

发现异常时，记这四样最有用：

1. 点的是首页哪一张卡片、哪个按钮。
2. 当前 Aira 地址栏显示什么。
3. 页面底部“页面事件日志”最后几行是什么。
4. 现象是空白、卡进度、跳外部 App、回退、打不开弹窗、opener 消息没回来，还是标题/颜色/快照不对。

## 覆盖场景

- 普通同标签链接、锚点、编码回调 URL、协议相对链接。
- 302 多段重定向、类似循环重定向、HTTP `Refresh`、meta refresh、JavaScript 跳转。
- OAuth / SSO：同标签授权、弹窗授权、`target=_blank`、`window.open`、opener `postMessage`、多段重定向、callback 后 `history.replaceState` 清理。
- POST 表单、POST 后 `303`、保留方法的 `307`、支付返回页。
- `about:blank` + `document.write`、延迟弹窗跳转、连续弹窗、子窗口给 opener 发消息。
- `tel:`、`mailto:`、`sms:`、`weixin://`、`alipay://`、`market://`、假的 `aira-lab://`，以及 Web fallback。
- iframe 导航、iframe 里的 `target=_blank`、iframe 自定义 scheme、frame 给 parent 发消息。
- JS `alert`、`confirm`、`prompt`、连续弹窗、`beforeunload` 离开确认。
- 慢响应、流式分块、延迟 title/favicon/theme-color、长滚动、视觉采样、延迟内容快照。
- 下载：`Content-Disposition`、重定向到下载、内联 MIME、`download` 属性、Blob URL、城通网盘式网页内下载后保存。
- 怪 URL：超长 URL、重复参数、嵌套 URL、编码重定向、callback-like hash、状态码和 MIME 异常。
