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
| 依赖 | apt-get、systemctl、git |

**域名（可选但推荐）**：需要一个指向服务器 IP 的域名（A 记录），用于 WordPress 站点 URL 和 Let's Encrypt SSL 证书。没有域名也能装，网站通过服务器 IP 访问（仅 HTTP）。

---

## 2. 快速安装

三步搞定：

```bash
# 1. 克隆仓库
git clone https://github.com/cdsi-project/cdsi-bootstrap.git
cd cdsi-bootstrap

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
| **3 查看密码** | 显示已安装组件的密码（MySQL/Redis/WordPress），按任意键返回 |
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
  4. Redis        (Redis数据库)
  5. Supervisor   (进程守护)
  6. Certbot      (SSL证书)
  7. WordPress    (WordPress站点)
```

- **选 0**：按依赖顺序安装全部 7 个组件，完成后自动输出验收报告并退出。
- **选 1-7**：单独安装某个组件（已安装的会自动跳过，幂等）。

### 3.3 七个组件说明

| # | 组件 | 作用 | 幂等跳过条件 |
|---|------|------|-------------|
| 1 | Nginx | Web 服务器，反向代理 PHP-FPM | nginx 已装 + active + `nginx -t` 有效 |
| 2 | MySQL | 数据库，存储 WordPress 数据 | mysql 服务 active |
| 3 | PHP-FPM | PHP 运行时，执行 WordPress | php + php-fpm 二进制存在 + mysqli 已加载 |
| 4 | Redis | 内存缓存 | redis-server 服务 active |
| 5 | Supervisor | 进程守护（为后续 M1+ 队列/任务准备） | supervisor 服务 active |
| 6 | Certbot | Let's Encrypt SSL 证书自动签发与续期 | 证书已存在则跳过签发 |
| 7 | WordPress | 站点应用，配置 Nginx + 安装 WP + 签 SSL | WP 已装（core is-installed） |

**推荐安装顺序**：选 0（全部安装），安装器会按正确依赖顺序执行。单独安装时请按 1→2→3→4→5→6→7 的顺序。

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

- 安装 Certbot 组件（第 6 项）时，自动通过 Let's Encrypt ACME HTTP-01 验证签发免费 SSL 证书。
- **前提**：域名 DNS A 记录已指向服务器 IP，且 80 端口对公网可达。
- 签发后自动配置 Nginx 80→443 重定向，并启用 `certbot.timer` 自动续期。
- 证书邮箱默认 `admin@<域名>`（如 `admin@cdsi.example.com`），想用其他邮箱可覆盖：

```bash
sudo CDSI_CERT_EMAIL=you@example.com ./install.sh
```

### 4.3 SSL 速率限制

Let's Encrypt 对同一域名 168 小时（7 天）内最多签发 5 张证书。如果反复重装触发限制：

```
[FAIL] Let's Encrypt rate limit reached — certificate NOT issued.
[FAIL]   retry after 2026-08-18 20:39:42 UTC
[FAIL]   The site stays HTTP-only for now.
```

这是正常降级行为——安装继续，网站先用 HTTP 跑。等冷却时间过后重跑：

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
  ● redis-server    active
  ● supervisor      active

═══ 网站地址 ═══
  前台:   https://cdsi.example.com
  后台:   https://cdsi.example.com/wp-admin/
  前台访问: 200 OK ✓

═══ 登录凭据 ═══
  WordPress:
    user: cdsi
    pass: ********
  MySQL root:
    pass: ********
```

密码文件存储在 `password/` 目录（mode 600，不提交到 git）：

| 文件 | 内容 |
|------|------|
| `password/mysql.pass` | MySQL root 密码 + cdsi 用户密码 |
| `password/redis.pass` | Redis 密码 |
| `password/wordpress.pass` | WordPress 管理员用户名 + 密码 |

随时通过主菜单「3 查看密码」查看。

---

## 6. 单独操作

### 6.1 单独安装某组件

```bash
sudo bash scripts/install-nginx.sh
sudo bash scripts/install-mysql.sh
sudo bash scripts/install-php.sh
sudo bash scripts/install-redis.sh
sudo bash scripts/install-supervisor.sh
sudo bash scripts/install-certbot.sh
sudo bash scripts/install-wordpress.sh
```

每个脚本独立可用，幂等（已装则跳过）。

### 6.2 卸载

```bash
sudo ./uninstall.sh
```

菜单提供 7 项单项卸载 + 全部卸载。支持 `--dry-run`（预览不执行）和 `--yes`（跳过确认）：

```bash
# 预览会卸载什么
sudo ./uninstall.sh --dry-run

# 全部卸载（不询问确认）
sudo ./uninstall.sh --yes 0
```

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
sudo ./install.sh   # 选 1 → 选 7（WordPress）
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

### Q: 如何修改 MySQL root 密码？

密码在安装时随机生成并存储在 `password/mysql.pass`。修改密码后同步更新文件：

```bash
mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '新密码';"
echo "root:新密码" > password/mysql.pass
chmod 600 password/mysql.pass
```

---

## 9. 文件结构

```
cdsi-bootstrap/
├── install.sh                    # 主安装器入口
├── uninstall.sh                  # 卸载器
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
│   ├── check-env.sh              # 环境检查（M1+）
│   ├── configure.sh              # 配置（M1+）
│   └── health.sh                 # 健康检查（M1+）
├── lib/
│   ├── common.sh                 # 颜色、常量、工具函数
│   ├── logger.sh                 # 日志
│   └── system.sh                 # 系统工具
├── password/                     # 密码文件（gitignored，安装时生成）
│   ├── mysql.pass
│   ├── redis.pass
│   └── wordpress.pass
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

M0（Node Bootstrap）完成后，CDSI 将进入 M1（Creator Identity）阶段。详见 [README.md](README.md) 的 Roadmap 章节。
