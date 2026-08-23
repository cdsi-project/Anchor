# CDSI 安装向导

从一台干净的受支持 Linux 服务器到可访问的 CDSI 节点，全流程指南。

---

## 1. 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Ubuntu Server 24.04/26.04 LTS、Debian 13，或 CentOS Stream 10 |
| 架构 | `x86_64` 或 `aarch64` |
| 权限 | root 或 sudo 用户 |
| CPU | 最低 1 核 |
| 内存 | 最低 1 GB，推荐 2 GB |
| 根分区可用空间 | 最低 10 GB，推荐 20 GB |
| 端口 | 80（HTTP）对公网开放；启用 HTTPS 时还需开放 443 |
| 依赖 | systemd、git、curl、sha256sum，以及 APT 或 DNF |

**域名（可选但推荐）**：使用指向服务器的裸域名（例如
`cdsi.example.com`，不要带协议、端口或路径）作为 WordPress 站点 URL，并可
申请 Let's Encrypt 证书。没有域名也能安装，默认通过 `http://<服务器 IP>`
访问。主安装器需要交互式终端；组件和配置脚本可独立运行。

Nginx、数据库和 PHP 基础栈使用操作系统默认软件源。Ubuntu/Debian 路径检测到
nginx.org、Ondrej/Sury PHP 等冲突源时会停止并提示先移除，不会静默改写服务器
的软件源。Debian 13 默认安装 `default-mysql-server` 提供的 MySQL-compatible
MariaDB 11.8、PHP 8.4 和 Certbot 4.0。CentOS 路径不启用 Remi；Certbot 需要
EPEL，安装器只会从 CentOS
Extras 安装 `epel-release`，并记录由 Anchor 添加的仓库状态。PHP 图片处理使用
GD，不安装 Imagick。

---

## 2. 快速安装

Debian 13 最小化系统在克隆仓库前先准备 Git 和 CA 证书：

```bash
sudo apt update
sudo apt install -y git ca-certificates
```

三步搞定：

```bash
# 1. 克隆仓库
git clone https://github.com/cdsi-project/Anchor.git
cd Anchor

# 2. 运行安装器（需要 root）
sudo ./install.sh

# 3. 按提示操作（见下方详解）
```

安装器会先做系统预检（Preflight Check），通过后进入主菜单。

---

## 3. 安装菜单

### 3.1 主菜单

Preflight 通过后，按任意键进入主菜单：

```
╔════════════════════════════════╗
║       CDSI 主菜单              ║
╠════════════════════════════════╣
║  1. 安装服务                   ║
║  2. 卸载服务                   ║
║  3. 查看密码                   ║
║  4. 配置域名                   ║
║  5. 配置 HTTPS                 ║
║  q. 退出                       ║
╚════════════════════════════════╝
```

| 选项 | 说明 |
|------|------|
| **1 安装服务** | 进入组件安装子菜单 |
| **2 卸载服务** | 调用 `uninstall.sh`，可选全部卸载或单项卸载 |
| **3 查看密码** | 显示已安装组件的密码（MySQL/WordPress，以及独立安装时的 Redis），按任意键返回 |
| **4 配置域名** | 验证 DNS 后激活域名；解析未就绪时只保存 pending 状态 |
| **5 配置 HTTPS** | 为当前域名签发证书；IP HTTPS 使用独立命令显式启用 |
| **q 退出** | 退出安装器 |

### 3.2 组件安装菜单

选择「1 安装服务」后，如果尚未配置域名，会先提示输入域名：

```
域名 (Domain, optional — for WordPress URL + SSL; leave empty to use the server IP): _
```

- 输入域名（如 `cdsi.example.com`）后，Anchor 会先严格校验 DNS。所有 A 记录
  必须是本服务器公网 IPv4；如果存在 AAAA 记录，每一条也必须属于本服务器。
- 校验成功才写入 `config/domain` 并作为活动域名。解析缺失、指向其他地址或
  无法可靠查询时，候选值写入 `config/domain.pending`，当前 WordPress URL 和
  Nginx 站点不变；首次安装则继续使用服务器 IP。
- 直接回车跳过域名，网站默认通过 `http://<服务器 IP>` 访问。

IP 模式会优先复用已有 WordPress 公网 URL，否则通过多个 HTTPS 端点探测并
校验公网 IPv4。若服务器网络阻止这些端点，显式指定公网 IP：

```bash
sudo CDSI_SERVER_IP=YOUR_PUBLIC_IPV4 ./install.sh
```

将 `YOUR_PUBLIC_IPV4` 替换为服务器真实公网 IPv4。纯内网部署必须显式提供 IP；
若希望从本机接口自动选择私网地址，同时设置
`CDSI_ALLOW_PRIVATE_IP=true`。自动模式不会把 `10/8`、`172.16/12`、
`192.168/16` 等私网地址写入 WordPress。

然后进入组件菜单：

```
  0. 安装全部组件
  1. Nginx        (HTTP服务)
  2. MySQL        (数据库)
  3. PHP-FPM      (PHP程序)
  4. Certbot      (SSL证书)
  5. WordPress    (WordPress站点)
```

- **选 0**：按实际依赖顺序安装全部 5 个可见组件，完成后自动输出验收报告并退出。内部会先创建 WordPress/Nginx 站点块，再执行最终 Certbot 步骤；证书失败时保留 HTTP 站点并在摘要中标记。
- **选 1-5**：单独运行某个组件。脚本会检查并复用现有状态，必要时继续协调配置，而不是一律整项跳过。

### 3.3 五个可见组件说明

| # | 组件 | 作用 | 重跑行为 |
|---|------|------|----------|
| 1 | Nginx | Web 服务器，反向代理 PHP-FPM | 复用已运行且配置有效的 Nginx，并重新协调全局 tuning |
| 2 | MySQL | 数据库，存储 WordPress 数据 | 仅在 root/cdsi 凭据完整且 root 认证成功时快速复用；否则继续修复配置 |
| 3 | PHP-FPM | PHP 运行时，执行 WordPress | PHP-FPM 运行且全部必需扩展已加载时快速复用；全新安装会补齐所需扩展 |
| 4 | Certbot | Let's Encrypt SSL 证书签发与续期 | 无活动域名时只安装并保持 HTTP；已有证书时验证后复用 |
| 5 | WordPress | 站点应用，配置 Nginx + 安装 WP | 已安装 core 仍会协调 URL、权限、Nginx 和 Beacon Application Password |

**推荐方式**：选 0，由安装器内部按 Nginx → MySQL → PHP-FPM → WordPress →
Certbot 执行。没有域名或 DNS 尚未生效时，Certbot 安全延期，站点继续使用
HTTP；解析修复后可从主菜单选择“配置域名”和“配置 HTTPS”，或运行第 4 节的
独立命令。

---

## 4. 域名与 SSL 证书

### 4.1 三种访问状态

| 状态 | 本地记录 | 当前网站 |
|------|----------|----------|
| 无域名 | 没有 `config/domain` | 默认 `http://<服务器公网 IP>` |
| 域名待解析 | `config/domain.pending` | 保持原有 WordPress URL 和 Nginx 配置；新站保持 IP HTTP |
| 域名已生效 | `config/domain` | 先使用 `http://<域名>`，证书成功后切换为 HTTPS |

不要用 `echo` 直接改这两个状态文件。域名变更同时涉及 DNS、WordPress URL 和
Nginx 配置，应使用下面的独立命令。

### 4.2 单独配置或清除域名

```bash
# 校验 DNS，成功后激活域名
sudo bash scripts/configure-domain.sh example.com

# 清除活动域名，切回服务器 IP 的 HTTP 站点
sudo bash scripts/configure-domain.sh --clear
```

域名命令要求所有 A 记录严格等于本服务器公网 IPv4。AAAA 记录不是必需的，
但只要存在，每一条就必须属于本服务器实际配置的公网 IPv6。任一记录错误、
缺少 A 记录或解析状态无法确认时，命令以延期状态退出，将候选域名保存到
`config/domain.pending`，并且不修改现有 WordPress URL 或 Nginx 站点。

修复 DNS 后重新运行同一命令即可激活域名并删除 pending 状态。切回 IP 模式
需要 Anchor 能确定服务器地址；自动探测受限时显式传入：

```bash
sudo env CDSI_SERVER_IP=YOUR_PUBLIC_IPV4 \
  bash scripts/configure-domain.sh --clear
```

将示例地址替换为服务器真实地址。

### 4.3 单独配置 HTTPS

为活动域名签发证书：

```bash
sudo bash scripts/configure-https.sh
```

也可以在一次命令中先校验并激活指定域名，再签发证书：

```bash
sudo bash scripts/configure-https.sh example.com
```

域名证书使用 Let's Encrypt ACME HTTP-01 验证。80 端口必须能从公网访问；
签发成功后 Anchor 配置 Nginx HTTPS 和 HTTP→HTTPS 重定向，并更新 WordPress
URL。证书邮箱默认 `admin@<域名>`，可覆盖：

```bash
sudo env CDSI_CERT_EMAIL=you@example.com \
  bash scripts/configure-https.sh example.com
```

只有公网 IP 时，也可以显式尝试申请公信证书：

```bash
sudo bash scripts/configure-https.sh --ip
```

IP HTTPS 不是默认安装行为，并同时要求：

- 目标是可从公网验证的 IPv4，而不是内网、共享出口或保留地址；
- 系统安装的 Certbot 为 5.4 或更高版本，并实际提供 `--ip-address` 与
  `--preferred-profile`；
- 使用 Let's Encrypt `shortlived` profile，证书有效期约 6 天；
- Certbot 自动续期 timer 和 Nginx deploy hook 都能正常工作。

系统 Certbot 不满足能力要求时，命令会失败并保持原有 HTTP 站点。Anchor 使用
操作系统仓库提供的 Certbot，不额外承诺 CentOS Stream 10 当前 EPEL 包一定支持
IP 证书。Debian 13 默认源的 Certbot 4.0 支持域名 HTTPS，但不满足 IP 证书要求
的 5.4+ 能力。Anchor 不会用自签名证书冒充公信 HTTPS。

### 4.4 备用 ACME CA

默认 CA 是 Let's Encrypt。可显式配置备用 ACME directory，例如 ZeroSSL：

```bash
read -r -p "ZeroSSL EAB KID: " CDSI_EAB_KID
read -r -s -p "ZeroSSL EAB HMAC key: " CDSI_EAB_HMAC
printf '\n'
sudo env \
  CDSI_ACME_FALLBACK_SERVER=https://acme.zerossl.com/v2/DV90 \
  CDSI_ACME_FALLBACK_EAB_KID="$CDSI_EAB_KID" \
  CDSI_ACME_FALLBACK_EAB_HMAC_KEY="$CDSI_EAB_HMAC" \
  bash scripts/configure-https.sh example.com
unset CDSI_EAB_KID CDSI_EAB_HMAC
```

备用 CA 只在主 ACME directory 经有界网络探测后仍不可达时选择。只要主
directory 可达，后续的 DNS、CAA、HTTP-01 授权、证书校验或 CA 限额错误都
不会触发自动切换。ZeroSSL 必须同时提供 EAB KID 和 HMAC key；HMAC key 是
秘密，上例使用隐藏输入，避免把明文写入仓库、安装日志或命令历史。其他备用
CA 是否需要 EAB，以该 CA 的账户要求为准。

IP 证书不会使用备用 CA；当前受支持路径固定为 Let's Encrypt short-lived
certificate。

### 4.5 签发失败与速率限制

证书签发失败是可恢复的降级，不会破坏当前 HTTP 站点。先按错误修复 DNS、
CAA、端口 80 或网络问题；遇到 CA 限额时等待错误给出的重试时间，不要反复
强制申请，也不要依赖备用 CA 绕过限额。然后重新运行：

```bash
sudo bash scripts/configure-https.sh example.com
```

---

## 5. 安装后验证

「安装全部」完成后，自动输出验收报告。以下以域名 HTTPS 已成功配置为例；
仅使用 IP HTTP 时，Certbot timer 可能尚未启用：

```
═══ 服务状态 ═══
    Unit               Runtime        Boot
    nginx              active         enabled
    php8.x-fpm/php-fpm active         enabled
    mysql/mysqld       active         enabled
    certbot.timer      active         enabled

═══ 前台访问检查 ═══
  可访问 OK (HTTP 200)

═══ WordPress 网站与登录信息 ═══
  网站地址: https://cdsi.example.com
  后台地址: https://cdsi.example.com/wp-admin/
  登录用户: cdsi
  登录密码: ********

  CDSI Beacon OpenWeb 配置:
  源站域名: cdsi.example.com
  登录用户: cdsi
  应用名称: CDSI Beacon
  应用密码: ************************
```

Nginx、数据库与 PHP-FPM 只有同时达到 `active` 和 `enabled` 才算完成：服务
当前正在运行，并会在服务器重启后自动启动。HTTPS 配置成功时，系统提供的
`certbot.timer` 或 `certbot-renew.timer` 也必须同时为 active/enabled；找不到
或无法启用续期 timer 时，HTTPS 配置会明确失败，而不会报告自动续期已完成。

密码文件存储在 `password/` 目录（mode 600，不提交到 git）：

| 文件 | 内容 |
|------|------|
| `password/mysql.pass` | 数据库 root 认证状态 + cdsi 用户密码；Debian 的空 `root:` 表示保留 MariaDB `unix_socket` 认证 |
| `password/redis.pass` | Redis 密码（仅独立安装 Redis 时存在） |
| `password/wordpress.pass` | WordPress 管理员用户名 + 登录密码 |
| `password/wordpress-beacon.pass` | CDSI Beacon 用户名 + WordPress Application Password |

从 Atlas 升级的节点仍可继续使用旧的 `password/wordpress-atlas.pass`；安装器会自动识别该文件，不会自动轮换已有 Application Password。

随时通过主菜单「3 查看密码」查看。

---

## 6. 单独操作

### 6.1 独立运行配置或组件脚本

```bash
# 域名和 HTTPS 生命周期
sudo bash scripts/configure-domain.sh example.com
sudo bash scripts/configure-domain.sh --clear
sudo bash scripts/configure-https.sh example.com
sudo bash scripts/configure-https.sh --ip

# 基础组件
sudo bash scripts/install-nginx.sh
sudo bash scripts/install-mysql.sh
sudo bash scripts/install-php.sh
sudo bash scripts/install-wordpress.sh
sudo bash scripts/install-certbot.sh
sudo bash scripts/install-redis.sh
sudo bash scripts/install-supervisor.sh
```

每个脚本独立可用，并以幂等重跑为目标：已满足的步骤会复用，配置协调或缺失
验证仍可能继续执行。日常域名或证书变更优先使用 `configure-domain.sh` 和
`configure-https.sh`，不需要重装 WordPress 或其他基础服务。

默认组件的公开脚本会先检测操作系统，再进入平台目录。Ubuntu 24.04/26.04、
Debian 13 与 CentOS Stream 10 路由均已实现。Redis 与 Supervisor 兼容脚本仍
仅支持 Ubuntu。

Ubuntu 和 Debian 安装脚本的 `apt-get` 操作都带有有界重试。遇到系统启动后的
`unattended-upgrades`、`apt-daily` 等进程占用 DPKG 锁时，单次最多等待
120 秒，失败后间隔 10 秒重试，最多执行 3 次。安装器不会删除锁文件、
终止系统更新进程，也不会因 DPKG 锁无限等待。

CentOS 的 DNF 操作同样最多执行 3 次，每次命令限制为 900 秒，失败后间隔
10 秒重试。脚本不会删除 DNF/RPM 锁，也不会终止系统更新进程。

CentOS 上若 firewalld 正在运行，Nginx 安装会分别补充缺失的永久与运行时
`http`/`https` 服务规则，并按 `permanent:http`、`runtime:http` 这类分层记录
Anchor 新增的状态到 `/etc/cdsi/firewall-added-services`。即使永久规则已存在，
脚本也会补齐缺失的运行时规则；卸载时只回滚 marker 中对应的层。
SELinux 不会被关闭；启用状态下会为 WordPress 配置持久文件上下文及数据库连接
布尔值。卸载时只按 Anchor marker 回滚这些变更。

Redis 和 Supervisor 暂不出现在 `install.sh` 的交互菜单和“安装全部”流程中；
兼容脚本 `scripts/install-redis.sh` 与 `scripts/install-supervisor.sh` 仍保留，
仅可在受支持 Ubuntu 上按需独立运行。卸载菜单仍保留对应选项，用于清理
Ubuntu 历史版本或独立安装的服务；Debian 与 CentOS 路径会保护性跳过这两项。

WP-CLI 与 WordPress 安装包优先从国内 CDN 下载。所有来源下载的文件都必须
匹配仓库中的 `SHA256SUMS` 才会安装或解压；校验失败时会丢弃文件并尝试
HTTPS 备用源。CDN 文件升级后，应先与可信来源交叉验证，再更新固定哈希。

install-wordpress.sh 独立运行或从安装菜单单独执行完成后，也会在最后集中显示网站地址、后台地址、WordPress 登录用户、后台密码和 CDSI Beacon Application Password。密码通过终端直接显示，不写入持久安装日志。

### 6.2 卸载

```bash
sudo ./uninstall.sh
```

菜单提供 7 项单项卸载 + 全部卸载。支持 `--dry-run`（预览不执行）和 `--yes`（跳过确认）：

```bash
# 预览全量或单组件会卸载什么
sudo ./uninstall.sh --dry-run all
sudo ./uninstall.sh --dry-run mysql

# 全部卸载（不询问确认）
sudo ./uninstall.sh --yes all
```

单项和全量卸载都是破坏性操作。卸载器没有安装来源清单，会按包名和固定路径处理服务器上的全局资源：例如 MySQL/MariaDB 卸载会删除整个 `/var/lib/mysql`；CentOS 上只额外删除 Anchor 自有的 `/etc/my.cnf.d/zz-cdsi-anchor.cnf`，Debian 上只额外删除 `/etc/mysql/mariadb.conf.d/99-cdsi-anchor.cnf`，不会删除平台的整个数据库配置目录。Certbot 卸载会处理 `/etc/letsencrypt` 中的全部证书，WordPress 卸载会删除全局 `/usr/local/bin/wp`，Nginx/PHP/Redis 也会按包名清理。它只适用于专用 CDSI 测试/节点服务器，不适合同时承载其他网站、数据库或共享运行时的混合服务器。

先对准备执行的同一目标运行 `--dry-run` 并核对输出；`--yes` 只应在已备份且确认清理范围后使用。卸载会清理所选组件的密码文件，但保留仓库中的 `config/domain`、`config/domain.pending` 和独立配置助手创建的 `/etc/cdsi`，便于审计或重装。全量卸载仅在 `/etc/cdsi/epel-added` 存在且内容有效时删除 Anchor 添加的 EPEL；预先存在的 EPEL 不会被移除。

---

## 7. 自定义 Nginx 配置

站点块配置模板在 `config/nginx-site.conf.template`，使用占位符：

| 占位符 | 替换为 |
|--------|--------|
| `{{WP_DOMAIN}}` | 域名（如 `cdsi.example.com`） |
| `{{WP_DIR}}` | WordPress 目录（`/var/www/wordpress`） |
| `{{PHP_UPSTREAM}}` | PHP-FPM upstream（例如 Unix socket） |

修改模板后重跑安装即可生效：

```bash
# 改模板
vim config/nginx-site.conf.template

# 重新应用
sudo ./install.sh   # 选 1 → 选 5（WordPress）
```

全局 Nginx 调优（gzip 类型、SSL session cache、server_tokens 等）由 `install-nginx.sh` 自动写入 `/etc/nginx/conf.d/cdsi-tuning.conf`。

---

## 8. 常见问题

### Q: 安装卡在 "Enter admin email" 不动？

已修复——邮箱默认 `admin@<域名>`，不再交互提示。如果看到此提示说明代码版本较旧，`git pull` 更新。

### Q: `nginx -t` 报 `conflicting server name`？

Nginx 自带的 `default` 站点可能被 Certbot 污染。安装 WordPress 时会自动禁用 `default` 站点。手动修复：

```bash
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### Q: SSH 连接服务器时 `stty erase` 报错？

无害，可忽略。安装器会尝试设置 Backspace 键映射，非交互终端下会跳过。

### Q: WordPress 后台登录密码在哪？

```bash
cat password/wordpress.pass
# 或安装器主菜单选 3
```

CDSI Beacon 使用独立、可撤销的 WordPress Application Password：

```bash
cat password/wordpress-beacon.pass
```

Application Password 的明文只在创建时由 WordPress 返回。若 WordPress 中的 `CDSI Beacon`（或升级前的 `CDSI Atlas`）记录仍存在、但该凭据文件丢失，安装器不会静默创建重复凭据；请先显式轮换该记录，再重新运行 WordPress 安装脚本。旧节点的 `password/wordpress-atlas.pass` 继续受支持。

Beacon 的“源站域名”配置只接受裸域名（例如 `cdsi.example.com`），不要填写 `https://`、端口或路径。Beacon 固定通过 HTTPS 发布；IP 安装或证书尚未生效时，安装器会保存 Application Password，但会将 Beacon 标记为暂不可用。

### Q: 输入域名后为什么网站仍显示 IP？

查看候选状态：

```bash
cat config/domain.pending
```

这表示 A 记录尚未全部指向本服务器，或存在错误的 AAAA 记录。Anchor 不会在
解析未确认时改动现站。修复 DNS 并等待生效后重新运行：

```bash
sudo bash scripts/configure-domain.sh example.com
sudo bash scripts/configure-https.sh
```

### Q: 只有 IP，能使用 HTTPS 吗？

公网 IPv4 可以尝试：

```bash
sudo bash scripts/configure-https.sh --ip
```

它要求系统 Certbot 5.4+，使用有效期约 6 天的 Let's Encrypt short-lived
证书，并依赖 active/enabled 的自动续期 timer。系统包版本不足、IP 不是公网
地址或 ACME directory 不可达时，Anchor 保持 HTTP。CentOS Stream 10 的当前
EPEL Certbot 版本不作支持承诺；Debian 13 默认 Certbot 4.0 明确不满足 IP 证书
能力要求，但仍支持域名 HTTPS。

### Q: 如何修改数据库 root 认证？

Ubuntu 与 CentOS Stream 的 MySQL root 密码在安装时随机生成并存储在
`password/mysql.pass`。修改密码后同步更新文件：

```bash
mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '新密码';"
sudo sed -i 's/^root:.*/root:新密码/' password/mysql.pass
sudo chmod 600 password/mysql.pass
```

上面的 `sed` 只更新 `root:` 行，会保留同一文件中的 `cdsi:` 应用凭据。若密码包含会被 `sed` 解释的字符，请手动编辑该行并再次确认文件权限为 600。

Debian 13 的 MariaDB root 认证由系统默认的 `unix_socket` 提供，使用
`sudo mariadb` 管理；Anchor 不生成 root 密码，`password/mysql.pass` 中的空
`root:` 行用于标记该认证状态。不要执行上面的改密命令，否则会破坏安装器和
卸载器依赖的 socket 认证契约。应用程序始终使用文件中的 `cdsi:` 密码连接。

---

## 9. 文件结构

```
Anchor/
├── install.sh                    # 主安装器入口
├── uninstall.sh                  # 卸载器
├── SHA256SUMS                    # CDN 下载文件的固定 SHA-256
├── config/
│   ├── nginx-site.conf.template  # Nginx 站点块模板
│   ├── domain                    # 已验证且活动的域名（gitignored）
│   └── domain.pending            # DNS 未就绪的候选域名（gitignored）
├── scripts/
│   ├── dispatch.sh               # 操作系统检测与平台路由
│   ├── configure-domain.sh       # 独立域名激活、清除入口
│   ├── configure-https.sh        # 独立域名/IP HTTPS 入口
│   ├── install-nginx.sh          # 可独立运行的公开入口
│   ├── install-mysql.sh          # 可独立运行的公开入口
│   ├── install-php.sh            # 可独立运行的公开入口
│   ├── install-redis.sh
│   ├── install-supervisor.sh
│   ├── install-certbot.sh
│   ├── install-wordpress.sh
│   ├── check-env.sh              # 当前安装器使用的环境预检
│   ├── common/                   # 默认组件的共享实现
│   ├── ubuntu/                   # 已实现的平台路由
│   ├── debian/                   # 已实现的 Debian 13 平台路由
│   ├── centos-stream/            # 已实现的平台路由
│   ├── configure.sh              # 可独立运行，尚未接入主安装流程
│   └── health.sh                 # 未来 doctor 的占位实现
├── lib/
│   ├── apt.sh                    # apt-get 锁等待与有界重试
│   ├── dnf.sh                    # DNF 超时与有界重试
│   ├── bootstrap.sh              # POSIX 入口转入 Bash 实现
│   ├── common.sh                 # 颜色、常量、工具函数
│   ├── domain.sh                 # A/AAAA 校验与 active/pending 状态
│   ├── logger.sh                 # 日志
│   ├── packages.sh               # APT/DNF 软件包操作与 EPEL 边界
│   ├── platform.sh               # 系统检测与平台支持矩阵
│   ├── services.sh               # systemd 服务操作
│   ├── system.sh                 # 系统工具
│   └── wordpress-access.sh       # WordPress / Beacon 最终访问信息
├── tests/
│   ├── test-apt.sh               # apt-get 重试单元测试
│   ├── test-dnf.sh               # DNF 重试单元测试
│   ├── test-install-order.sh     # 安装全部依赖顺序/Certbot 降级测试
│   ├── test-packages.sh          # APT/DNF/EPEL 软件包抽象测试
│   ├── test-platform.sh          # 平台检测与路由约束测试
│   ├── test-preflight.sh         # 支持版本与安全状态预检测试
│   ├── test-services.sh          # systemd 服务抽象测试
│   └── test-uninstall.sh         # 卸载 dry-run/数据库认证保护测试
├── password/                     # 密码文件（gitignored，安装时生成）
│   ├── mysql.pass
│   ├── redis.pass
│   ├── wordpress.pass
│   └── wordpress-beacon.pass
├── templates/
│   └── certbot-deploy-hook.sh    # 续期后安全 reload Nginx
├── docs/                         # 文档
├── AGENTS.md                     # AI Agent 工程契约
├── README.md
├── INSTALL.md                    # 本文件
└── LICENSE
```

---

## 10. 日志与排错

安装日志：`/var/log/cdsi/install.log`

```bash
# 查看最近安装日志
tail -50 /var/log/cdsi/install.log

# 查看某个组件的安装输出
grep "Installing Nginx" /var/log/cdsi/install.log
```

Nginx 错误日志：`/var/log/nginx/wordpress.error.log`
Certbot 日志：`/var/log/letsencrypt/letsencrypt.log`

---

## 下一步

M0（Node Anchor）完成后，CDSI 将进入 M1（Creator Identity）阶段。详见 [README.md](README.md) 的 Roadmap 章节。
