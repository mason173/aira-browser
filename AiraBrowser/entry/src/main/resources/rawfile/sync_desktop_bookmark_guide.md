# 私有化部署教程

私有化部署是你自己的同步服务器。手机和电脑配对到同一台服务器后，可以同步书签、历史记录、个性化设置和小说书架，也可以使用网页接力和跨设备标签页。

它不需要华为账号，也不需要 Aira Pro。一台服务器只给一个人用，没有注册、密码账号或会员。每台设备单独配对，使用同一个配对码。断开连接只会移除这台设备的连接，不会删除手机或电脑上已有的浏览数据。

服务器管理员可以读取同步过去的数据。不要把这台服务器暴露到不受信任的网络上。

## 开始前准备

- 一台能运行 Docker 的电脑或服务器。
- 手机上的 Aira。
- 电脑浏览器中的 Aira-sync 扩展。Chrome、Edge 和 Firefox 都可以。
- 手机和电脑如果在同一台可信局域网里，可以使用 HTTP。只要流量会离开这台局域网，就使用 HTTPS。

## 一、启动服务器

在这台仓库的 `services/personal-server` 目录执行：

```bash
cp .env.example .env
docker compose up -d --build
docker compose exec aira-server cat /data/setup-code
```

最后一条命令打印配对码。手机、电脑以及其他设备都填这一个码。服务器不会在配对后删除它，也不会让它过期。请把它当成密码保管。

默认只监听本机的 `127.0.0.1:8787`。跑服务器的这台电脑上的浏览器可以访问它，手机访问不到。

## 二、让手机能够访问

只在跑服务器的电脑上连接扩展时，地址用：

```text
http://127.0.0.1:8787
```

手机也要连接时，先让服务器能被手机访问到。

同一台家庭网络里，把 `compose.yaml` 的端口改成对局域网开放，然后重新启动：

```yaml
ports:
  - "8787:8787"
```

```bash
docker compose up -d
```

手机里填写电脑的局域网地址，例如 `http://192.168.1.20:8787`。只在你信任的网络里这样做。不要把 `8787` 直接暴露到公网。

要在家庭网络以外使用，在前面加一层受信任的 HTTPS 反向代理，并在 `.env` 里写上对外地址：

```dotenv
AIRA_PUBLIC_URL=https://sync.example.com
```

Caddy 可以这样转发：

```caddyfile
sync.example.com {
  reverse_proxy 127.0.0.1:8787
}
```

用 Nginx 时，只配 `location /` 还不够。宝塔、aaPanel 这类面板会给每个站点生成一条静态的 `/.well-known` 规则用于证书验证；Nginx 按最长前缀匹配，`/.well-known` 比 `/` 长，`/.well-known/aira` 会被它截走并返回 404 页面，手机端会提示“连接失败”。加一条精确匹配即可，`/.well-known/acme-challenge/` 的证书续签不受影响：

```nginx
location = /.well-known/aira {
  proxy_pass http://127.0.0.1:8787;
}
```

反向代理要保留 `Authorization` 请求头，并把请求体上限设到 12 MiB 或更高。不要用手机和电脑都不信任的自签名证书。

改完后可以先在电脑上确认服务还在：

```bash
curl --fail --silent http://127.0.0.1:8787/health
```

手机浏览器也应能打开你准备填写的那个地址下的 `/health`，以及 `/.well-known/aira`：前者返回 `{"ok":true,...}`，后者应该是一段 JSON，而不是 404 页面。

## 三、在手机上配对

1. 打开 Aira，进入「设置」-「同步」，选择「私有化部署」。也可以从「与电脑互联」页进入同一页。
2. 服务器地址填手机能够打开的地址，不要在末尾加路径。
3. 配对码填上一步打印出来的码。
4. 设备名称可以保留默认。
5. 点「连接并配对」。

同一个配对码可以配所有设备。每台设备会各自保存自己的设备凭据，不会把华为账号令牌、会员信息或付款数据发给这台服务器。

## 四、在电脑上安装并配对

复制对应浏览器的插件链接，发到电脑后打开。商店入口属于 Official 发行版；Community 发行版不上架插件商店。

- [Chrome 插件链接](https://chromewebstore.google.com/detail/aira-focused-webdav-new-t/hgifgplkfbfmkogjdpcjkgbgkikcjpni?authuser=0&hl=zh-CN)
- [Edge 插件链接](https://microsoftedge.microsoft.com/addons/detail/afliopnmelmcajnmldmiklifmbchgfni)
- [Firefox 插件链接](https://addons.mozilla.org/zh-CN/firefox/addon/aira-focused-webdav-new-tab)

Community 发行版，或无法通过商店安装时，从 GitHub Releases 下载本地安装包：

- [从 GitHub Releases 下载 Community 安装包](https://github.com/mason173/aira-browser/releases)

安装后：

1. 点击浏览器工具栏上的 Aira-sync 图标。
2. 选择「连接私有化部署」。
3. 服务器地址填和手机相同的地址。跑服务器的这台电脑自己连接时，可以填 `http://127.0.0.1:8787`。
4. 填入和手机相同的配对码，点「连接并使用」。

手机和电脑使用同一个配对码。每台设备配对后会各自拿到一份设备凭据，断开其中一台不会影响其他设备。

## 五、打开与电脑互联

配对完成后，在手机 Aira 进入「设置」-「与电脑互联」，打开「与电脑互联」。私有化部署不看登录状态，也不看 Aira Pro。

电脑端 Aira-sync 保持打开。之后可以：

- 在手机标签页管理里查看电脑当前打开的普通网页，或在电脑扩展里查看手机标签页。
- 从手机把当前网页推送到已配对的电脑。

只显示当前在线或刚刚在线的设备。设置页、新标签页和扩展页不会出现在跨设备标签页里。

## 常见问题

- 手机打不开地址：`127.0.0.1` 指的是手机自己，不是服务器。改用电脑的局域网地址，或 HTTPS 对外地址。
- 提示配对码无效：码复制错了，或服务器已经换过配对码。到服务器上重新查看 `/data/setup-code`，并去掉复制时带上的空格和换行。
- 提示不是兼容的私有化部署、无法解析的响应，或这个地址上没有同步服务（HTTP 404）：地址没有指向这台服务器，或反向代理没有把 `/.well-known/aira` 原样转过去。用 Nginx/宝塔时，通常是面板自带的 `/.well-known` 静态目录截走了请求，按上面的 `location = /.well-known/aira` 修好即可。
- 电脑连上了、手机没有：两边必须填写各自能访问的同一台服务器，不能一台填本机地址、另一台填一个到不了的地址。
- 同步不是备份。服务器上的数据库就是你的数据，请另行保留备份。
