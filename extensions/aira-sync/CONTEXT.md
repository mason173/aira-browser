# Aira-sync

Aira-sync connects one desktop browser installation to Aira Browser through either a paired Personal Server or, in the
Official distribution, an Aira Desktop Device Session. Background capabilities continue without requiring the popup to
stay open. Community operation has no account or membership dependency.

## Language

**桌面设备会话 (Desktop Device Session)**:
一份 Aira 官方账号与某个桌面设备之间的长期配对关系，仅用于 Official 发行版的 Aira Cloud。同一账号可以同时拥有多个互不替换的桌面设备会话；会话可以暂时离线，但只有在未配对或凭证被撤销时才需要用户重新操作。
_Avoid_: 登录状态、桌面登录

## Release Identity

The Official local-install Chrome/Edge package is separate from the Community/open-source package and must retain the
legacy Chromium extension ID `plnjjlkaaonbccmjpfljbbbbaahfklem`. Run `npm run pack:local-official` to inject its fixed
public manifest key into a staging copy and produce `Aira-Sync-Official-v<version>.zip`; never add that key to the
source manifests or store packages. Community remains `Aira-sync-v<version>.zip` with its own fixed identity.

**桌面设备 (Desktop Device)**:
一个独立的桌面浏览器插件安装实例。它在同一 Aira 账号下拥有稳定身份，以支持多设备并存和后续精确推送。
_Avoid_: 电脑登录、当前电脑

**设备凭证 (Device Credential)**:
用于证明某个桌面设备会话有效的、长期且可撤销的服务器凭证；每个插件安装实例独立持有。凭证不按时间自动过期，只在明确退出、撤销或数据清除时失效。
_Avoid_: desktopPushToken、登录 token

**网页推送广播 (Page Push Broadcast)**:
手机未指定目标设备时，一次网页推送会为发送当时在线的每个桌面设备建立独立投递。各设备分别领取和确认自己的投递，不通过竞争领取同一个任务；离线设备不会在恢复在线后补收历史网页，没有在线设备时不建立投递。
_Avoid_: 默认设备推送、任意设备抢单

**在线桌面设备 (Online Desktop Device)**:
最近持续向 Aira 后端报告活动、当前可接收网页推送的桌面设备。长期有效但没有近期活动的设备会话不等于在线设备。
_Avoid_: 已登录设备、所有历史设备

**功能意愿 (Capability Preference)**:
用户对网页推送或云书签同步作出的持续选择。功能意愿按桌面设备与 Aira 账号隔离，独立于当前网络、Pro 资格和设备会话状态；同账号重新连接时恢复，切换账号时不继承旧账号的云同步意愿。
_Avoid_: 功能状态、当前是否可用

**Pro 功能资格 (Pro Capability Entitlement)**:
账号当前是否有权运行某项 Pro 功能的服务端判定。它独立于桌面设备会话；资格检查暂时失败不等于资格不存在。
_Avoid_: 登录状态、Pro 获取结果
