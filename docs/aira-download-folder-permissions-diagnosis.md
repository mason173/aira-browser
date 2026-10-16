# 下载文件夹授权与回退诊断

日期：2026-10-15。诊断基线：`b077651e`。

## 结论与证据边界

代码存在两个可以在确定性交错下复现的缺陷：持久授权携带临时专用权限位，以及并发写入检查共用探针文件。
它们都能沿真实的目录服务、导出服务和 V2 完成处理方法，走到自选目录失败、回退系统目录的分支。
截图中的提示来自 Aira 的 `download_completed_custom_folder_unavailable`，不是系统随机修改下载目录。

测试使用华为文档约束建模 fileShare 与文件 IO，运行生产代码。它能证明代码与平台契约不一致、共享探针存在竞争，
不能代替特定用户设备上的日志或真机复测，也不能据此断言截图发生时具体命中了哪一个缺陷。

## 当前路径链路

普通下载先写应用私有临时文件，完成后才由 `DownloadV2Service.persistFinishedDownload()` 导出：

1. 完成时读取当前下载设置，若选择了自定义目录，先激活其持久授权。
2. `DownloadFileResolutionService.persistToDirectory()` 调用写入探针；探针失败就不再尝试正式文件写入。
3. 自选目录导出成功后返回该目录的 URI。
4. 自选目录失败后，`persistToSystemDownloads()` 先尝试 `Download/Aira`；失败再调用系统 Picker 的 DOWNLOAD 模式。
5. 系统默认下载位置可能是 `Download/<bundleName>`，官方包对应截图中的 `Download/com.aira.browser`。
6. V2 将这次回退标记为 `customDirectoryBypassed`，完成提示显示实际位置并要求重新选择文件夹。

私密下载有独立保存策略，不能用普通下载的自定义目录分支推断其行为。
下载确认框里的位置选择修改的是全局下载设置，不是单个任务的固定目标；下载期间修改设置可能影响完成时的目标。

## 缺陷一：持久授权携带 CREATE_MODE

原代码的统一策略为 `READ_MODE | WRITE_MODE | CREATE_MODE`，即数值 `7`，同时用于 persist、activate 和 revoke。

华为 `PolicyInfo` 明确规定 CREATE、DELETE、RENAME 仅用于临时授权；父目录具有写权限时，创建子文件无需另加 CREATE。
持久化及其后续激活应使用 `READ_MODE | WRITE_MODE`，即 `3`。

后果是：选择器提供的临时授权仍有效时可以写入，但持久化失败后设置仍保存该目录。应用退出后临时授权消失，
再激活时无法恢复。即便以前已有合法的读写持久授权，使用含 CREATE 的策略激活也不符合契约。

修复：统一改为读写模式；保留 `BusinessError.data` 中每条策略的错误码与原因，区别 INVALID_MODE、
PERMISSION_NOT_PERSISTED 等情况。旧版没有成功保存下来的授权，需用户通过 Picker 重新选择一次，不能靠保存的 URI 自动补授权。

## 缺陷二：共享写入探针造成误判

原代码每次都创建、截断并清理同一个 `<directory>/.aira-write-probe`。
设置页检查和多个完成下载可以同时调用该方法。交错顺序为：

1. 两个调用均完成写入并关闭同名探针。
2. 调用 A 完成 stat 后 unlink。
3. 调用 B 执行 stat，发现文件已不存在，返回目录不可写。
4. V2 将 B 的下载回退到系统目录，尽管目录授权一直有效。

修复：每次调用使用独立 UUID 探针；写入失败时也关闭描述符；只清理本次创建的探针。
这同时避免截断用户目录里恰好同名的 `.aira-write-probe` 文件。

## 另外发现的问题与限制

- 默认位置文案固定为“我的手机/Download/Aira”，但代码有系统目录回退，不能保证始终位于 Aira 子目录。
  本次将四种语言的设置值改为“系统下载目录”，下载完成仍显示实际位置。
- 四个选择入口分别处理设置与授权：下载设置页、嵌入设置面板、下载管理页、下载确认框。前几个入口会提示临时授权，
  确认框则没有区分持久授权结果。部分入口异步保存设置，却在保存成功前开始释放旧授权；保存失败时可能回到失去持久授权的旧配置。
  这是后续需要统一到设置事务 owner 的风险，本次未改写这些入口。
- “探针仅作建议”的注释只适用于选择阶段；完成导出阶段实际把探针失败作为回退条件。此前只改设置入口或完成提示，不能修复权限位或探针竞争。
- 华为不保证手工拼接或重复编解码的 URI 可用，远端 URI 也不支持持久化。本次没有证据认定这就是截图的直接原因，
  也没有把 URI 转为路径来绕过权限检查。特殊目录、文档提供方或系统版本问题仍应结合错误明细验证。
- 手机目录选择受 FolderSelection 系统能力约束，不能把任意设备、任意目录都承诺为长期可写。

## 验证

运行 `node scripts/check-aira-download-directory-lifecycle.cjs`：

- 选择目录、临时写入、模拟退出重启、再次完成下载。
- 恢复已经存在的读写持久授权。
- 两个完成下载交错检查、清理探针。
- 真正撤销授权后仍正确回退并标记旁路。
- 激活失败保留每条策略的诊断原因。
- 探针写入失败关闭文件，保留用户已有的同名文件。

修复前，前三个场景失败。仅去掉 CREATE_MODE 后，前两个通过，并发场景仍失败；独立探针后全部通过。
原有 `check-aira-download-export-ghost-guard.cjs` 保留。新测试接入 Client CI 和构建脚本。

首轮 Community 无签名 HAP 编译通过，随后安装官方 Debug 版 3.8.2（1000537）供复现。

## 后续真机复现：Documents 的探针 URI 打开失败

用户将目录设为 Documents 后仍发生回退。通过设备端按 `DownloadLocationDirectory` 和
`DownloadFileResolution` 标签过滤日志，确认 23:15:50 的选择检查和 23:16:09 的完成导出检查均在
`fileIo.open(file://docs/storage/Users/currentUser/Documents/.aira-write-probe-<id>, CREATE | READ_WRITE)`
处返回 `13900002 / No such file or directory`，随后直接回退，没有尝试写入正式下载文件。

该证据确定了此前用例未覆盖的实际失败点，但没有证明 Documents 禁止写入，也没有证明失败的具体平台原因。
首轮测试的文件 IO 模型假定有效目录可以通过子 URI 的 open(CREATE) 创建文件，这个假定不能覆盖该设备行为。

新增复现模型：父目录有效、持久授权有效、新子 URI 的 open(CREATE) 返回 ENOENT，但 URI-copy 支持创建目标。
修正前用例回退，修正后在这个分支创建应用缓存探针源，使用与正式导出相同的 `fileIo.copy(sourceUri, targetUri)`，
再校验目标大小。权限拒绝或零字节结果仍失败并清理探针，禁止使用公开目录的路径写入绕过权限检查。

加入临时诊断：选择和激活结果、父目录 stat、探针使用的 transport、copy 失败阶段和具体错误码。
原始设备日志包含私人文件名，不写入仓库。

官方 Debug 诊断版 3.8.2（1000538）安装后，用户在同一 Documents 目录复测成功，并通过文件管理器确认文件存在。
23:26 的限定标签日志进一步确认：

- Picker 选择结果成功持久化，访问模式为读写 `3`。
- 激活持久授权成功，父目录 stat 返回 `directory=true`。
- 原先的新子文件 URI open 仍然返回 ENOENT。
- URI-copy 探针写入并校验了 10 字节。
- 正式导出源文件与 Documents 目标文件均为 116965943 字节；未进入系统目录回退。

因此本机这次问题确认是用 open(CREATE) 的失败结果过早否定整个目录，Documents 本身可以使用。
这不能推广为所有文档提供方都支持相同 URI 创建行为，持久授权跨进程重启尚未单独真机复测。
确认后移除选择、激活和父目录检查的临时诊断代码，保留正常导出所需的复制探针结果与分阶段错误日志，并停止本地日志采集。
2026-10-16 收尾：清理后的九个生命周期回归用例及原有空文件防护检查通过；官方 Debug 版 3.8.2（1000539）编译成功并覆盖安装到同一手机。

## 华为官方依据

通过 HarmonyOS Developer Knowledge MCP 搜索并读取完整文档：

- [文件分享：OperationMode、PolicyInfo、persistPermission、activatePermission](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-fileshare)
- [授权持久化：退出后重激活及授权保留配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission)
- [选择器：FolderSelection、DocumentSelectMode、DOWNLOAD 模式](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker)
- [应用文件分享：URI 构造注意事项](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-app-file)
- [文件 IO：open 的 URI 支持、copy 的源和目标 URI、stat 与 unlink 的参数差别](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-fs)

通用网页抓取部分页面超时；具体 API 条款以 MCP 返回的华为全文为依据。
