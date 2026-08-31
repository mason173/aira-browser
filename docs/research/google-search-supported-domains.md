# Google Search 国家/地区域名来源与 UA allowlist 边界

核验日期：2026-08-29

## 结论

Google 在第一方域名上公开提供 [`https://www.google.com/supported_domains`](https://www.google.com/supported_domains)。本次直接请求得到 `HTTP 200`，正文是 187 行 ASCII 文本；每行一个以 `.` 开头的 Google 域名。列表明确包含 `.google.com.hk`，也包含 `.google.co.uk`、`.google.co.jp`、`.google.de` 等国家或地区域名。

把每行的**一个前导点**去掉后，可为每个来源域名生成两个精确 Host：裸域名和 `www.` 域名。当前 187 个来源域名会得到 374 个不重复 Host。例如：

```text
google.com.hk
www.google.com.hk
google.co.uk
www.google.co.uk
```

这份来源适合作为 Aira Google Search UA 规则的上游输入，但它不是带版本和 schema 承诺的公开 API。Aira 应在构建或发布云端规则时抓取、严格校验、固定成一个可审计 revision，再通过现有签名清单下发；客户端不应运行时直接依赖该端点。

## 第一方来源核验

### 支持域名列表

来源：Google 第一方端点 [`https://www.google.com/supported_domains`](https://www.google.com/supported_domains)

2026-08-29 的实测结果：

- 请求没有发生重定向，直接返回 `HTTP/2 200`。
- 响应服务器标识为 `gws`。
- `Content-Type` 是 `text/html; charset=ISO-8859-1`，但正文实际是无 HTML 标记的逐行 ASCII 域名列表；解析器不能依赖 `text/plain`。
- `Cache-Control` 是 `private, max-age=0`，没有版本号、ETag 或稳定性声明。
- 正文为 2,355 字节、187 行，末尾有换行。
- SHA-256 为 `ba827017007f54b698de62a5e3bb290327c12ddc0f9c88503511725c0baf3c49`。该摘要只记录本次核验快照，不能当成未来响应必须永久不变的常量。
- 187 行全部以 `.` 开头；去掉一个前导点后，全部是小写 ASCII，并以 `google.` 开头。
- 没有空行、重复项、通配符、`accounts`、`googleusercontent` 或其他非 `google.*` 域名。
- `.google.com.hk` 位于本次响应第 71 行。
- 使用 `Accept: text/plain`、中文或英文 `Accept-Language` 再请求，正文摘要与上述结果相同。这只能证明本次响应不随这些请求头变化，不能视为 Google 的长期兼容保证。

### `google.com.hk` 主机行为

来源：[`https://google.com.hk/`](https://google.com.hk/) 与 [`https://www.google.com.hk/`](https://www.google.com.hk/)

本次 HEAD 核验显示，裸域名返回 `301` 并跳转到 `https://www.google.com.hk/`，`www` 主机返回 `200`。因此两者都必须在 UA allowlist 中：裸域名规则保证第一次请求已经使用兼容 UA，`www` 规则保证重定向后的请求继续使用兼容 UA。不能只添加最终落点。

## 安全生成规则

推荐把 Google 返回列表视为**待验证的上游数据**，按以下规则生成 Aira 精确 allowlist：

1. 只接受 HTTPS 请求成功且最终状态为 `200` 的响应；设置合理超时和正文大小上限。
2. 按行解析，最多移除行尾的 `\r`，拒绝空行。
3. 每行必须恰好以一个 `.` 开头。只移除这个前导点，不把它解释成子域通配符。
4. 规范化后的值必须是合法的小写 ASCII DNS Host、以 `google.` 开头、没有端口、路径、用户信息、通配符或尾随点；同时拒绝重复项。
5. 对每个通过校验的域名只生成 `domain` 和 `www.domain` 两个 Host。本次结果应为 187 个来源域名、374 个生成 Host。
6. 规则匹配应使用 URL 解析器得到的规范化 `hostname` 做集合精确匹配，而不是对完整 URL 做字符串前缀/包含判断。
7. 抓取失败、格式异常、数量突降、出现非 `google.*` 项或校验失败时，必须拒绝发布并保留上一版已签名清单，不能发布空列表或部分列表。
8. 发布前记录来源 URL、抓取时间、来源条目数、生成 Host 数、内容摘要和清单 revision，并保留可复核 diff。云端和 App 内置兜底应由同一份已审查快照生成。

## 明确的匹配边界

生成后的规则只覆盖列表声明的 Google Search 域名的裸域名和 `www` 主机。

允许的例子：

```text
google.com
www.google.com
google.com.hk
www.google.com.hk
google.co.jp
www.google.co.jp
```

不应由这条规则覆盖：

```text
accounts.google.com
mail.google.com
maps.google.com
news.google.com
googleusercontent.com
example-google.com
google.com.example.com
```

不要使用 `google.*`、`*.google.*`、`startsWith("google.")` 或 `contains("google")`。这些写法既会扩大到没有经过上游声明的 Google 服务，也可能误命中攻击者控制的域名。正文里的前导点也不能被直接转换成“所有子域”规则。

如果以后确实需要兼容 Google 的另一个产品子域，应为该产品建立独立、可解释的精确规则和验证用例，不能借 Search 国家域名列表顺带放开。

## 可复现核验

```bash
curl --silent --show-error --location --max-time 20 \
  --dump-header /tmp/google-supported-domains.headers \
  --output /tmp/google-supported-domains.txt \
  https://www.google.com/supported_domains

wc -c -l /tmp/google-supported-domains.txt
shasum -a 256 /tmp/google-supported-domains.txt
rg -n '^\.google\.com\.hk$' /tmp/google-supported-domains.txt

sed 's/^\.//' /tmp/google-supported-domains.txt \
  | awk '{ print; print "www." $0 }' \
  | sort -u \
  | wc -l
```

`curl --location` 适合观察未来是否增加重定向，但生产生成器还应记录最终 URL，并限制只能留在预期的 Google HTTPS 主机边界内，避免无审计地跟随来源变化。

## 证据边界

- `supported_domains` 是 Google 第一方、机器可读的当前列表，因此比社区维护的国家域名文章更适合作为生成输入。
- 该响应没有内嵌说明、版本字段或公开 schema；`Content-Type` 也不是 `text/plain`。本文不能据此声称 Google 对端点格式或长期可用性作出了兼容承诺。
- 187 和 374 是 2026-08-29 核验时的数量，不应硬编码为永久业务常量。数量可以作为发布审查的异常信号，实际更新仍应经过校验和 diff 审核。
- 本文没有修改或发布 Aira 的 UA 规则，也没有验证某个具体 Google 错误页是否只由 UA 引起；它只确认域名来源和 allowlist 的安全生成边界。

## 来源

- Google supported domains：[`https://www.google.com/supported_domains`](https://www.google.com/supported_domains)
- Google Hong Kong 裸域名：[`https://google.com.hk/`](https://google.com.hk/)
- Google Hong Kong `www` 主机：[`https://www.google.com.hk/`](https://www.google.com.hk/)
