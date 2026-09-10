# Aira 第三方开源许可

Aira 使用的第三方组件保留其原作者的版权和许可证。本页是安装包内的索引；完整许可证文本随源码仓库或对应资源一并提供。

## HarmonyOS 客户端

- **curl 8.7.1**：curl License。完整文本见 `AiraBrowser/entry/src/main/cpp/third_party/curl/COPYING`。
- **Mbed TLS 3.6.2**：Apache-2.0 或 GPL-2.0-or-later。完整文本见 `AiraBrowser/entry/src/main/cpp/third_party/mbedtls/LICENSE`。
- **Mozilla Readability 0.6.0**：Apache-2.0。随包文件为 `mozilla-readability-LICENSE.txt` 和 `mozilla-readability-NOTICE.txt`。
- **adblock-rust 0.13.2**：MPL-2.0。随包文件为 `adblock-rust-LICENSE.txt`、`adblock-rust-NOTICE.txt` 和 `adblock-rust-THIRD-PARTY-LICENSES.txt`。
- **markdown-it**：MIT。随包文件为 `markdown-it-LICENSE.txt`。
- **原生下载依赖**：许可证清单见 `native-download-THIRD-PARTY-LICENSES.txt`。

## Aira-sync

扩展的 React、Radix UI、Tailwind CSS、i18next、qr-code-styling、lucide-react 等依赖及版本，见源码中的 `extensions/aira-sync/THIRD_PARTY_NOTICES.md` 和 `package-lock.json`。其中 `lucide-react` 使用 ISC 许可证。

## Personal Server

Personal Server 的运行时依赖和许可证，见源码中的 `services/personal-server/THIRD_PARTY_NOTICES.md` 和 `package-lock.json`。

## 图标资源

- Tabler Icons 3.46.0 线框 SVG 和 Aira Operational Icon 字体使用 MIT 许可证。许可证文本见
  `resources/icon-sources/aira/vendor/lucide/aira-operational-icons/LICENSE`。历史目录名 `lucide/` 仅保留路径兼容，运行时图形已不是 Lucide。
- Gravity UI 2.20.0 图标使用 MIT 许可证，许可证文本见 `resources/icon-sources/aira/vendor/gravity-ui/2.20.0/LICENSE`。
- Aira 为保持已有 ArkTS 代码点和语义 ID，保留了历史资源路径和映射字段名；这些兼容标识不代表旧图形仍在运行时使用。

本页不替代各组件随附的完整许可证文本。修改或再分发 Aira 时，请保留对应版权声明、许可证文本和变更说明。
