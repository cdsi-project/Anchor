# CDSI 安装向导

从一台干净的 Ubuntu 服务器到可访问的 CDSI 节点，全流程指南。

---

## 1. 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Ubuntu Server 24.04 LTS 或 26.04 LTS |
| 权限 | root 或 sudo 用户 |
| 内存 | ≥ 1 GB |
| 端口 | 80（HTTP）、443（HTTPS）对公网开放 |
| 依赖 | apt-get、systemctl、git、curl、sha256sum |

**域名（可选但推荐）**：需要一个指向服务器 IP 的裸域名（A 记录，例如 `cdsi.example.com`，不要带协议、端口或路径），用于 WordPress 站点 URL 和 Let's Encrypt SSL 证书。没有域名也能装，网站通过服务器 IP 访问（仅 HTTP）。主安装器需要交互式终端；组件脚本可独立运行。

Nginx 和 PHP 只使用 Ubuntu 系统默认 APT 源。安装器检测到 nginx.org、Ondrej PHP/Nginx PPA 等冲突源时会停止并提示先移除，不会静默改写服务器的软件源。

---

## 2. 快速安装

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
║  q. 退出                       ║
╚════════════════════════════════╝
```

| 选项 | 说明 |
|------|------|
| **1 安装服务** | 进入组件安装子菜单 |
| **2 卸载服务** | 调用 `uninstall.sh`，可选全部卸载或单项卸载 |
| **3 查看密码** | 显示已安装组件的密码（MySQL/WordPress，以及独立安装时的 Redis），按任意键返回 |
| **q 退出** | 退出安装器 |

### 3.2 组件安装菜单

选择「1 安装服务」后，如果尚未配置域名，会先提示输入域名：

```
域名 (Domain, optional — for WordPress URL + SSL; leave empty to use the server IP): _
```

- 输入域名（如 `cdsi.example.com`），会保存到 `config/domain`，后续安装自动读取。
- 直接回车跳过，网站用服务器 IP 访问（无 SSL）。

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
| 3 | PHP-FPM | PHP 运行时，执行 WordPress | PHP-FPM 运行且 `mysqli` 已加载时快速复用；全新安装会补齐所需扩展 |
| 4 | Certbot | Let's Encrypt SSL 证书自动签发与续期 | 无域名时只安装；已有证书时复用并重新协调 Nginx SSL 配置 |
| 5 | WordPress | 站点应用，配置 Nginx + 安装 WP + 签 SSL | 已安装 core 仍会协调 URL、权限、Nginx 和 Beacon Application Password；单独运行时尝试 SSL |

**推荐方式**：选 0，由安装器内部按 Nginx → MySQL → PHP-FPM → WordPress → Certbot 执行。单独安装时先按 1→2→3→5；WordPress 会在域名站点块创建后尝试 Certbot，DNS 尚未就绪时可修复后再选 4。

---

## 4. 域名与 SSL 证书

### 4.1 域名配置

首次安装输入域名后，会保存到 `config/domain`（不提交到 git）。后续重装自动读取，不再询问。

```bash
# 手动设置域名（跳过交互提示）
echo "cdsi.example.com" > config/domain
sudo ./install.sh
```

### 4.2 SSL 证书

- 安装 Certbot 组件时，自动通过 Let's Encrypt ACME HTTP-01 验证签发免费 SSL 证书。
- **前提**：域名 DNS A 记录已指向服务器 IP，且 80 端口对公网可达。
- 签发后自动配置 Nginx 80→443 重定向。存在 `certbot.timer` 时启用 systemd 定时续期，否则保留 Certbot 包提供的 cron 续期机制。
- 证书邮箱默认 `admin@<域名>`（如 `admin@cdsi.example.com`），想用其他邮箱可覆盖：

```bash
sudo CDSI_CERT_EMAIL=you@example.com ./install.sh
```

### 4.3 SSL 签发失败与速率限制

Let's Encrypt 的签发受 DNS、端口连通性及其当前速率限制约束。如果反复重装触发限制，安装器会输出类似信息：

```
[FAIL] Let's Encrypt rate limit reached — certificate NOT issued.
[FAIL]   retry after 2026-08-18 20:39:42 UTC
[FAIL]   The site stays HTTP-only for now.
```

这是正常降级行为：安装继续，网站先用 HTTP 运行。修复 DNS/端口问题或等待错误信息中的重试时间后再运行：

```bash
sudo bash scripts/install-certbot.sh
```

---

## 5. 安装后验证

「安装全部」完成后，自动输出验收报告：

```
═══ 服务状态 ═══
  ● nginx           active
  ● php8.5-fpm      active
  ● mysql           active

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

密码文件存储在 `password/` 目录（mode 600，不提交到 git）：

| 文件 | 内容 |
|------|------|
| `password/mysql.pass` | MySQL root 密码 + cdsi 用户密码 |
| `password/redis.pass` | Redis 密码（仅独立安装 Redis 时存在） |
| `password/wordpress.pass` | WordPress 管理员用户名 + 登录密码 |
| `password/wordpress-beacon.pass` | CDSI Beacon 用户名 + WordPress Application Password |

从 Atlas 升级的节点仍可继续使用旧的 `password/wordpress-atlas.pass`；安装器会自动识别该文件，不会自动轮换已有 Application Password。

随时通过主菜单「3 查看密码」查看。

---

## 6. 单独操作

### 6.1 单独安装某组件

```bash
sudo bash scripts/install-nginx.sh
sudo bash scripts/install-mysql.sh
sudo bash scripts/install-php.sh
sudo bash scripts/install-wordpress.sh
sudo bash scripts/install-certbot.sh
sudo bash scripts/install-redis.sh
sudo bash scripts/install-supervisor.sh
```

每个脚本独立可用，并以幂等重跑为目标：已满足的步骤会复用，配置协调或缺失验证仍可能继续执行。

所有安装脚本的 `apt-get` 操作都带有有界重试。遇到系统启动后的
`unattended-upgrades`、`apt-daily` 等进程占用 DPKG 锁时，单次最多等待
120 秒，失败后间隔 10 秒重试，最多执行 3 次。安装器不会删除锁文件、
终止系统更新进程，也不会因 DPKG 锁无限等待。

Redis 和 Supervisor 暂不出现在 `install.sh` 的交互菜单和“安装全部”流程中；
兼容脚本 `scripts/install-redis.sh` 与 `scripts/install-supervisor.sh` 仍保留，
可按需独立运行。卸载菜单仍保留对应选项，用于清理历史版本或独立安装的服务。

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

单项和全量卸载都是破坏性操作。卸载器没有安装来源清单，会按包名和固定路径处理服务器上的全局资源：例如 MySQL 卸载会删除整个 `/var/lib/mysql`，Certbot 卸载会处理 `/etc/letsencrypt` 中的全部证书，WordPress 卸载会删除全局 `/usr/local/bin/wp`，Nginx/PHP/Redis 也会按包名清理。它只适用于专用 CDSI 测试/节点服务器，不适合同时承载其他网站、数据库或共享运行时的混合服务器。

先对准备执行的同一目标运行 `--dry-run` 并核对输出；`--yes` 只应在已备份且确认清理范围后使用。卸载会清理所选组件的密码文件，但保留仓库中的 `config/domain` 和独立配置助手创建的 `/etc/cdsi`，便于审计或重装。

---

## 7. 自定义 Nginx 配置

站点块配置模板在 `config/nginx-site.conf.template`，使用占位符：

| 占位符 | 替换为 |
|--------|--------|
| `{{WP_DOMAIN}}` | 域名（如 `cdsi.example.com`） |
| `{{WP_DIR}}` | WordPress 目录（`/var/www/wordpress`） |
| `{{PHP_SOCK}}` | PHP-FPM socket 路径 |

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

### Q: 如何修改 MySQL root 密码？

密码在安装时随机生成并存储在 `password/mysql.pass`。修改密码后同步更新文件：

```bash
mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '新密码';"
sudo sed -i 's/^root:.*/root:新密码/' password/mysql.pass
sudo chmod 600 password/mysql.pass
```

上面的 `sed` 只更新 `root:` 行，会保留同一文件中的 `cdsi:` 应用凭据。若密码包含会被 `sed` 解释的字符，请手动编辑该行并再次确认文件权限为 600。

---

## 9. 文件结构

```
Anchor/
├── install.sh                    # 主安装器入口
├── uninstall.sh                  # 卸载器
├── SHA256SUMS                    # CDN 下载文件的固定 SHA-256
├── config/
│   ├── nginx-site.conf.template  # Nginx 站点块模板
│   └── domain                    # 域名（gitignored，安装时生成）
├── scripts/
│   ├── install-nginx.sh
│   ├── install-mysql.sh
│   ├── install-php.sh
│   ├── install-redis.sh
│   ├── install-supervisor.sh
│   ├── install-certbot.sh
│   ├── install-wordpress.sh
│   ├── check-env.sh              # 当前安装器使用的环境预检
│   ├── configure.sh              # 可独立运行，尚未接入主安装流程
│   └── health.sh                 # 未来 doctor 的占位实现
├── lib/
│   ├── apt.sh                    # apt-get 锁等待与有界重试
│   ├── common.sh                 # 颜色、常量、工具函数
│   ├── logger.sh                 # 日志
│   ├── system.sh                 # 系统工具
│   └── wordpress-access.sh       # WordPress / Beacon 最终访问信息
├── tests/
│   ├── test-apt.sh               # apt-get 重试单元测试
│   ├── test-install-order.sh     # 安装全部依赖顺序/Certbot 降级测试
│   ├── test-preflight.sh         # Ubuntu 版本预检测试
│   └── test-uninstall.sh         # 卸载 dry-run/数据库认证保护测试
├── password/                     # 密码文件（gitignored，安装时生成）
│   ├── mysql.pass
│   ├── redis.pass
│   ├── wordpress.pass
│   └── wordpress-beacon.pass
├── templates/                    # 模板资源
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
