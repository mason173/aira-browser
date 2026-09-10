# Aira

Aira 是一套 GPL-3.0 的鸿蒙 NEXT 与桌面浏览器隐私浏览栈，源码在同一份仓库里。包含鸿蒙客户端、桌面扩展，以及用于自建同步的单所有者服务。

本文面向想要运行或改 Aira 的贡献者和开发者，说明公开源码边界，以及最短的本地开发路径。

## 界面

真实界面截图：

![手机界面](docs/screenshots/phone.webp)

![PC 界面](docs/screenshots/desktop.webp)

## 仓库约定

- 浏览器和扩展从**同一提交**打出 **Community** 或 **Official** 两种发行版。
- Community 构建不需要 Aira 生产凭证，也不依赖官方托管服务。
- Personal Server 是单所有者、配对设备服务。没有注册、密码账号、组织、角色、会员、计费、推荐或华为登录。
- 本地数据、WebDAV 和 Personal Server 不需要 Aira 会员。
- Aira 生产服务、Admin、华为项目配置、签名材料和部署密钥不在本仓库。

## 组件

| 组件 | 位置 | 开发职责 |
| --- | --- | --- |
| 鸿蒙客户端 | [`AiraBrowser/`](AiraBrowser/README.md) | ArkTS/ArkUI 浏览器壳、本地存储、Provider 接入 |
| 桌面扩展 | [`extensions/aira-sync/`](extensions/aira-sync/README.md) | Chromium/Firefox 界面、后台运行时、跨端客户端 |
| Personal Server | [`services/personal-server/`](services/personal-server/README.md) | Node.js/Docker 同步、配对、页面推送、标签在线 API |
| 共享资源 | [`resources/`](resources/) 与 [`docs/`](docs/) | 图标、声明、架构决策、协议文档 |

## 架构速览

客户端保存本地浏览状态，并在每个同步域上选择一个远程 Provider。公开可用的是 WebDAV 和 Personal Server；Official 构建还可以使用 Aira 云和华为云空间。

Personal Server 提供发现、一次性配对、书签、历史、个性化、小说书架、页面推送和跨端标签接口。它使用按设备签发的 bearer 凭证，只存储凭证哈希，没有用户账号系统。

改协议之前先读这些约定：

- [开源发行边界](docs/open-source-distribution.md)
- [Personal Server 自托管](docs/self-hosting.md)
- [Personal Server 协议](services/personal-server/docs/protocol.md)
- [Personal Server 运维](services/personal-server/docs/operations.md)
- [Aira-sync 开发说明](extensions/aira-sync/README.md)
- [鸿蒙客户端开发说明](AiraBrowser/README.md)

## 开发环境

| 范围 | 要求 |
| --- | --- |
| 仓库脚本 | `.node-version` / `.nvmrc` 中的 Node.js `18.20.8` |
| Aira-sync | Node.js 24.x 和 npm（见 `extensions/aira-sync/.node-version`） |
| Personal Server | Node.js 20 或更新，或带 Compose 的 Docker |
| 鸿蒙客户端 | DevEco Studio、HarmonyOS NEXT SDK/API 23 或更新，以及 `ohpm` |

克隆后默认在仓库根目录执行命令，除非某节另有说明：

```bash
git clone https://github.com/mason173/aira-browser.git
cd aira-browser
```

## 本地运行 Personal Server

不落持久数据、最快验证服务是否正常：

```bash
cd services/personal-server
npm ci
npm run check
```

用 Docker 跑一份会持久化的本地实例：

```bash
cd services/personal-server
cp .env.example .env
docker compose up -d --build
docker compose exec aira-server cat /data/setup-code
```

用打印出的一次性配对码连接开发客户端。默认 Compose 绑定 `127.0.0.1:8787`；要对外访问，先加 TLS 反代。备份、恢复、升级、反代和凭证吊销见服务 README 与运维文档。

## 构建 Aira-sync

```bash
cd extensions/aira-sync
npm ci
npm run typecheck
npm test
npm run build:community
```

Community 产物在 `build/community/`，可在 Chromium 内核浏览器里以未打包扩展加载。公开 Community 清单有固定扩展 ID `efehgppkhnkjamcpbipclfmmofdildji`。

Official 构建通过 `AIRA_SYNC_OFFICIAL_API_ROUTES` 注入私有路由，本仓库不含生产地址。完整路由字段和打包命令见扩展 README。

## 构建鸿蒙客户端

用 DevEco Studio 打开 `AiraBrowser/`，或使用根目录构建脚本：

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

这会打出供 CI 和源码核验用的未签名 Community HAP。装到设备需要 `org.aira.browser` 的本地签名。Official 构建另外需要私有 AGConnect、生产路由，以及 `com.aira.browser` 的签名：

```bash
AIRA_DISTRIBUTION=official SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

不要提交 `agconnect-services.json`、带加密密码的 build-profile、`.p12` / `.p7b` 或其他签名材料。Official 签名和装机脚本是私有打包流程，不在本仓库。Community 构建见 [`AiraBrowser/README.md`](AiraBrowser/README.md)。

## Community 与 Official

两种发行版共用源码和测试，差别只在构建时的身份和私有能力输入：

| 能力 | Community | Official |
| --- | --- | --- |
| 本地浏览与本地存储 | 可用 | 可用 |
| 用户自选 WebDAV | 可用 | 可用 |
| Personal Server 同步与跨端标签 | 可用 | 可用 |
| 华为账号 / 华为云空间 | 未配置 | 私有华为项目与审批 |
| Aira 云托管服务 | 未配置 | 私有服务路由与权益 |
| 华为 IAP / Aira Pro | 未配置 | 私有生产服务 |

增改 Provider 或发行边界前先读 [`docs/open-source-distribution.md`](docs/open-source-distribution.md)。不要长期分叉 Community，也不要把 Official 专用页面复制成第二套源码。

## 贡献流程

跨组件协议改动放在同一个 pull request，改到的组件都要跑检查。策略、传输、持久化和编排放进现有的 `core`、`services`、`data` 或 `features`，不要堆进原生 UI 壳。

提 PR 前：

```bash
# 仓库根目录
git diff --check

# Aira-sync 改动
(cd extensions/aira-sync && npm run typecheck && npm test)

# Personal Server 改动
(cd services/personal-server && npm run check)
```

评审要求见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，漏洞私下报告见 [`SECURITY.md`](SECURITY.md)。不要在 issue 或 PR 里附带设备数据、凭证、token、数据库、备份、浏览器配置或生产配置。

## 许可

Aira 原创源码按 [GPL-3.0-only](LICENSE) 提供。第三方组件保留各自许可，见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) 及各组件目录中的声明。

许可不授予 Aira 名称、标识或其他商标权利。见 [`TRADEMARKS.md`](TRADEMARKS.md)。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mason173/aira-browser&type=Date)](https://star-history.com/#mason173/aira-browser&Date)
