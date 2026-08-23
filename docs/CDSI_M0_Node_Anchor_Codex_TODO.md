# CDSI M0 — Node Anchor / Installer v0.1

> **CDSI — Creator Digital Sovereignty Infrastructure**  
> 本文档用于指导 Codex 实现 CDSI 的第一个工程里程碑：**从一台裸 Ubuntu Server 自动化部署出一个 HTTPS 可访问的 CDSI Node**。

> **文档状态（2026-08-22）：历史设计与进度记录。** 本文保留最初的
> Installer v0.1 目标、示例路径和未勾选清单，不代表当前实现状态。
> 当前事实以根目录 [README](../README.md)、[INSTALL](../INSTALL.md) 和
> [AGENTS](../AGENTS.md) 为准；当前入口是 `sudo ./install.sh`。

当前 M0 / Installer v0.3.0 进度：

| 状态 | 内容 |
| --- | --- |
| 已实现 | Ubuntu 24.04/26.04、Debian 13 与 CentOS Stream 10 路由、日志与预检、Nginx、MySQL/MariaDB、PHP-FPM、WordPress、域名、Certbot、组件级幂等、最终访问信息、Beacon Application Password、卸载、APT/DNF 重试、CDN SHA-256 校验；Debian 13 使用默认源 MariaDB 11.8、PHP 8.4 和 Certbot 4.0 |
| 独立可用 | Redis、Supervisor（仅 Ubuntu）；不进入主菜单和“安装全部” |
| 部分实现 | `/etc/cdsi` 配置助手、整机集成验收、持久日志与故障恢复 |
| 未实现 | Composer/CDSI Core 部署、`cdsi` CLI/doctor/update、断点续装、完整服务器备份恢复、队列 Worker |

---

## 1. 目标

CDSI M0 只解决一个问题：

> **用户拿到一台干净的 Ubuntu Server 后，通过一套自动化安装程序，完成 CDSI Node 所需基础环境、应用、域名和 HTTPS 的安装与配置。**

最终目标体验：

```bash
git clone https://github.com/cdsi-project/Anchor.git
cd Anchor
sudo ./install.sh
```

安装完成后：

```text
https://creator.example.com
```

可以正常访问 CDSI Node。

后续目标可逐步演进为：

```bash
cdsi install
cdsi status
cdsi doctor
cdsi update
```

---

# 2. v0.1 支持范围

第一版严格限制环境，优先把单一路径做稳定。

## 2.1 支持

```text
OS          Ubuntu Server LTS
Web         Nginx
Runtime     PHP-FPM
Package     Composer
Database    MySQL
Cache       Redis
Process     Supervisor
SSL         Let's Encrypt / Certbot
App         CDSI Core
```

## 2.2 暂不支持

```text
Debian 全版本
CentOS / Rocky / AlmaLinux
Docker
Kubernetes
Apache
PostgreSQL
多节点部署
负载均衡
HA
自动扩容
服务器面板
复杂多租户
对象存储自动配置
```

设计原则：

> **先把一条部署路径做到极稳，再扩兼容性。**

---

# 3. M0 完成定义

M0 不以“脚本写完”为完成标准。

必须满足：

1. 一台全新 Ubuntu VPS 可以直接运行 Installer。
2. 无需手工编辑 Nginx、PHP、MySQL 配置。
3. 自动安装 CDSI 运行环境。
4. 自动初始化 CDSI 数据库与应用账户。
5. 自动部署 CDSI Core。
6. 域名解析正确时自动配置 HTTPS。
7. 第二次执行 Installer 不破坏已有环境。
8. `cdsi doctor` 能正确检查节点健康状态。
9. 服务器 reboot 后所有必要服务自动恢复。
10. 最终用户可通过浏览器访问 CDSI Node。

---

# 4. 推荐目录结构

```text
cdsi/
├── app/
├── bootstrap/
├── config/
├── database/
├── public/
├── resources/
├── routes/
├── storage/
│
├── installer/
│   ├── install.sh
│   │
│   ├── lib/
│   │   ├── common.sh
│   │   ├── logger.sh
│   │   ├── system.sh
│   │   ├── config.sh
│   │   └── secrets.sh
│   │
│   ├── modules/
│   │   ├── nginx.sh
│   │   ├── php.sh
│   │   ├── mysql.sh
│   │   ├── redis.sh
│   │   ├── supervisor.sh
│   │   ├── certbot.sh
│   │   └── cdsi.sh
│   │
│   ├── templates/
│   │   ├── nginx.conf.tpl
│   │   ├── supervisor-worker.conf.tpl
│   │   └── env.tpl
│   │
│   └── checks/
│       ├── preflight.sh
│       └── health.sh
│
├── bin/
│   └── cdsi
│
├── README.md
└── ...
```

约束：

- 不要把所有逻辑写进一个超长 `install.sh`。
- 每个基础组件独立模块。
- 模板文件单独管理。
- CLI 与 Installer 分离。
- 业务应用逻辑与服务器安装逻辑分离。

---

# 5. Installer 模块接口规范

所有组件尽量遵循统一接口：

```bash
<module>_check
<module>_install
<module>_configure
<module>_verify
```

例如：

```bash
nginx_check
nginx_install
nginx_configure
nginx_verify
```

MySQL：

```bash
mysql_check
mysql_install
mysql_configure
mysql_verify
```

原则：

> 每个模块负责判断现状、安装、配置、验证，而不是假设服务器一定是空环境。

---

# 6. TODO 01 — Preflight 系统检查

安装任何东西之前，先判断服务器是否满足要求。

## 6.1 检查内容

```text
[ ] 当前用户
[ ] root / sudo 权限
[ ] Linux 发行版
[ ] Ubuntu 版本
[ ] CPU 架构
[ ] CPU 核心数
[ ] 内存
[ ] 剩余磁盘
[ ] Internet 连接
[ ] DNS 查询工具
[ ] 80 端口占用
[ ] 443 端口占用
[ ] apt 是否可用
[ ] Nginx 是否存在
[ ] PHP 是否存在
[ ] MySQL 是否存在
[ ] Redis 是否存在
[ ] Supervisor 是否存在
```

## 6.2 建议最低环境

初始建议：

```text
CPU        >= 1 Core
RAM        >= 1 GB
Disk Free  >= 10 GB
OS         Ubuntu LTS
```

建议区分：

```text
OK
WARNING
ERROR
```

例如低于推荐内存可以 warning，而不是立即退出。

## 6.3 示例输出

```text
CDSI Preflight Check
────────────────────────────────

OS              Ubuntu 24.04        OK
Architecture    x86_64              OK
CPU             2 Core              OK
Memory          3.8 GB              OK
Disk Free       42 GB               OK
Port 80         Available           OK
Port 443        Available           OK
Internet        Connected           OK

Nginx           Not Installed
PHP             Not Installed
MySQL           Not Installed
Redis           Not Installed

Ready to install CDSI.
```

---

# 7. TODO 02 — 日志系统

禁止在各模块中散落无结构的：

```bash
echo "installing..."
```

统一实现：

```bash
log_info
log_success
log_warning
log_error
```

示例：

```text
[INFO] Installing Nginx...
[ OK ] Nginx installed.
[INFO] Configuring MySQL...
[ OK ] Database created.
[WARN] DNS is not pointing to this server.
[FAIL] SSL certificate creation failed.
```

同时写入：

```text
/var/log/cdsi/install.log
```

失败时必须输出：

```text
Installation failed at: MYSQL_CONFIG
Log: /var/log/cdsi/install.log
```

---

# 8. TODO 03 — CDSI 配置系统

不要把域名、数据库名等配置散落在 Shell 脚本中。

建议生成：

```text
/etc/cdsi/cdsi.conf
```

可采用简单 KEY=VALUE，或者 YAML。

示例：

```yaml
domain: creator.example.com

app:
  path: /var/www/cdsi

database:
  host: 127.0.0.1
  port: 3306
  name: cdsi
  user: cdsi

redis:
  enabled: true

ssl:
  enabled: true

backup:
  enabled: false
```

敏感信息单独保存：

```text
/etc/cdsi/secrets.env
```

权限必须：

```bash
chmod 600 /etc/cdsi/secrets.env
```

---

# 9. TODO 04 — Secrets 生成器

实现统一随机密钥生成器，例如：

```bash
generate_secret 32
```

至少用于：

```text
DB_PASSWORD
SETUP_TOKEN
其他未来需要的服务密码
```

原则：

> **默认安全，不要求用户手工设计密码。**

Laravel 的 `APP_KEY` 优先使用：

```bash
php artisan key:generate
```

---

# 10. TODO 05 — Nginx 模块

实现：

```bash
nginx_check
nginx_install
nginx_configure
nginx_verify
```

完整流程：

```text
检测
↓
apt install nginx
↓
生成 CDSI site 配置
↓
创建 sites-enabled 链接
↓
nginx -t
↓
systemctl enable nginx
↓
systemctl restart nginx
↓
HTTP 健康检查
```

推荐配置路径：

```text
/etc/nginx/sites-available/cdsi
/etc/nginx/sites-enabled/cdsi
```

模板：

```text
installer/templates/nginx.conf.tpl
```

变量至少包括：

```text
{{DOMAIN}}
{{APP_PATH}}
{{PHP_SOCKET}}
```

不要通过几十条 `echo` 拼 Nginx 配置。

---

# 11. TODO 06 — PHP 模块

定义 CDSI PHP Runtime Specification。

第一版根据 CDSI Core / Laravel 实际依赖维护包列表，例如：

```bash
PHP_PACKAGES=(
  php-cli
  php-fpm
  php-mysql
  php-curl
  php-mbstring
  php-xml
  php-zip
  php-bcmath
  php-intl
  php-gd
)
```

流程：

```text
安装 PHP
↓
安装扩展
↓
识别 PHP-FPM socket
↓
配置必要 php.ini 参数
↓
启动 PHP-FPM
↓
systemctl enable
↓
安装 Composer
↓
验证 PHP / Composer / Extensions
```

检查：

```bash
php -v
php -m
composer --version
```

需要为创作资产上传预留配置入口：

```text
upload_max_filesize
post_max_size
memory_limit
max_execution_time
```

v0.1 只设置合理默认值，不做复杂媒体基础设施。

---

# 12. TODO 07 — MySQL 模块

实现：

```bash
mysql_check
mysql_install
mysql_configure
mysql_verify
```

自动完成：

```text
安装 MySQL
↓
启动并 enable
↓
创建 CDSI 数据库
↓
创建 CDSI 独立用户
↓
生成随机密码
↓
授予最小必要权限
↓
写入应用 .env
↓
验证应用数据库连接
```

默认：

```text
Database: cdsi
User:     cdsi
```

禁止 CDSI 应用直接使用 MySQL root。

目标配置：

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=cdsi
DB_USERNAME=cdsi
DB_PASSWORD=<generated>
```

重要：

> 不仅要验证 MySQL service running，还要验证 CDSI 应用实际可以连接数据库。

---

# 13. TODO 08 — Redis 模块

实现：

```bash
redis_check
redis_install
redis_configure
redis_verify
```

流程：

```text
安装 Redis
↓
启动
↓
enable
↓
redis-cli ping
↓
Laravel / CDSI 连接测试
```

基础检查：

```bash
redis-cli ping
```

期望：

```text
PONG
```

Redis 可用于：

```text
Cache
Queue
Session
Rate Limit
```

是否全部默认启用，由 CDSI Core 实际实现决定。

---

# 14. TODO 09 — Supervisor 模块

v0.1 只需要优先托管：

```text
Laravel Queue Worker
```

配置：

```text
/etc/supervisor/conf.d/cdsi-worker.conf
```

模板：

```text
installer/templates/supervisor-worker.conf.tpl
```

要求：

```text
自动启动
异常自动重启
www-data 用户运行
独立日志
服务器 reboot 后恢复
```

后续再扩展：

```text
Import Worker
Feed Worker
Media Worker
AI Worker
```

---

# 15. TODO 10 — CDSI Core 部署模块

实现：

```bash
cdsi_check
cdsi_install
cdsi_configure
cdsi_verify
```

流程：

```text
创建 /var/www/cdsi
↓
下载 Release / 使用当前源码
↓
设置 ownership / permission
↓
composer install
↓
创建 .env
↓
写入数据库、Redis、Domain 配置
↓
php artisan key:generate
↓
php artisan migrate --force
↓
php artisan storage:link
↓
Laravel optimize/cache
↓
启动 queue
↓
应用 Health Check
```

生产 Composer 示例：

```bash
composer install \
  --no-dev \
  --optimize-autoloader \
  --no-interaction
```

Laravel：

```bash
php artisan migrate --force
php artisan storage:link
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

注意：

- `route:cache` 等命令失败时必须清晰报错。
- 不要忽略命令 exit code。
- 文件权限必须最小化，不要无脑 `chmod -R 777`。

---

# 16. TODO 11 — Node Owner 初始化

Shell Installer 不负责复杂业务用户创建。

推荐流程：

```text
Installer
↓
生成一次性 SETUP_TOKEN
↓
CDSI Node 启动
↓
用户浏览器访问 /setup
↓
创建第一个 Node Owner
↓
SETUP_TOKEN 立即失效
```

安装完成提示：

```text
CDSI Node is ready.

Open:
https://creator.example.com/setup

Setup Token:
xxxxxxxx
```

安全要求：

- Setup Token 必须随机生成。
- 创建 Owner 后立即失效。
- 已初始化节点禁止再次进入首次安装流程。

---

# 17. TODO 12 — 域名检测

用户输入：

```text
creator.example.com
```

检查：

```text
A Record
AAAA Record（如适用）
当前服务器公网 IP
```

示例：

```text
Domain DNS Check              WARNING

creator.example.com:
1.2.3.4

This server:
5.6.7.8

Please update the DNS record.
CDSI installation will continue without SSL.
```

重要原则：

> DNS 不正确时，应用安装可以继续，HTTPS 阶段跳过或标记 pending，不要整个 Installer 失败。

---

# 18. TODO 13 — HTTPS / Certbot

当 DNS 正确时：

```text
安装 Certbot
↓
申请 Let's Encrypt Certificate
↓
配置 Nginx
↓
HTTPS 检查
↓
自动续期检查
```

最终状态：

```text
HTTPS                 OK
Certificate           Valid
Auto Renewal          Enabled
```

SSL 失败应属于可恢复失败：

```text
CDSI installed successfully.
SSL configuration failed.

Run after DNS is ready:
cdsi ssl
```

`cdsi ssl` 可在后续版本加入。

---

# 19. TODO 14 — Health Check / Doctor

实现：

```bash
cdsi doctor
```

至少检查：

## Infrastructure

```text
Nginx
PHP-FPM
MySQL
Redis
Supervisor
Queue Worker
```

## Application

```text
CDSI application boot
.env
Database connection
Storage writable
Laravel cache
Queue
Scheduler（如启用）
```

## Network

```text
Domain
HTTP
HTTPS
Certificate
```

## System

```text
Disk
Memory
Permissions
```

示例：

```text
CDSI Doctor
────────────────────────────────

Infrastructure
────────────────────────────────
Nginx            OK
PHP-FPM          OK
MySQL            OK
Redis            OK
Supervisor       OK
Queue            OK

Application
────────────────────────────────
Database         OK
Storage          OK
Config           OK

Network
────────────────────────────────
Domain           OK
HTTP             OK
HTTPS            OK

System
────────────────────────────────
Disk             OK
Memory           OK

CDSI Node is healthy.
```

---

# 20. TODO 15 — 幂等设计

Installer 必须支持重复执行。

原则：

> **重复执行应趋向同一个最终状态，而不是破坏已有环境。**

示例：

```text
Nginx             Installed        SKIP
PHP               Installed        SKIP
MySQL Database    Exists           SKIP
Redis             Running          SKIP
CDSI              Installed        VERIFY
SSL               Valid            SKIP
```

所有模块安装前先 `check`。

禁止：

- 重复创建数据库导致失败。
- 重置已有数据库密码。
- 覆盖用户已经存在的内容。
- 无条件覆盖 Nginx 配置。
- 无条件重新签发证书。
- 无条件重建 `.env`。

---

# 21. TODO 16 — 失败恢复 / Resume

Installer 需要记录执行阶段。

建议状态：

```text
SYSTEM
NGINX
PHP
MYSQL
REDIS
SUPERVISOR
CDSI
DOMAIN
SSL
FINISHED
```

失败示例：

```text
Installation partially completed.

Completed:
✓ System
✓ Nginx
✓ PHP
✓ MySQL
✓ Redis
✓ CDSI

Failed:
✗ SSL

Log:
/var/log/cdsi/install.log
```

未来支持：

```bash
cdsi install --resume
```

如果 v0.1 暂未实现完整 `--resume`，至少保证重新执行 Installer 能通过幂等逻辑继续完成。

---

# 22. CDSI CLI v0.1

路径：

```text
bin/cdsi
```

安装后：

```text
/usr/local/bin/cdsi
```

第一阶段实现：

```bash
cdsi version
cdsi status
cdsi doctor
cdsi update
```

Installer 负责安装流程。

后续预留：

```bash
cdsi install
cdsi backup
cdsi restore
cdsi ssl
cdsi domain
cdsi logs
cdsi restart
cdsi migrate
```

---

# 23. `cdsi status`

目标输出：

```text
CDSI Node
────────────────────────────────

Node            creator.example.com
Version         0.1.0

Services
────────────────────────────────

Nginx           ● Running
PHP-FPM         ● Running
MySQL           ● Running
Redis           ● Running
Queue           ● Running

Network
────────────────────────────────

HTTP            ✓
HTTPS           ✓
Certificate     Valid

Storage
────────────────────────────────

Disk            16%
Assets          2.8 GB

────────────────────────────────

Your node is healthy.
```

v0.1 不要求所有字段都立即实现，但输出格式和模块边界要可扩展。

---

# 24. `cdsi update`

v0.1 可先实现基础安全更新流程。

目标：

```text
检查当前版本
↓
检查可用 Release
↓
进入 maintenance
↓
备份必要配置
↓
下载 / 更新代码
↓
composer install
↓
migrate --force
↓
清理 / 重建 cache
↓
restart worker
↓
health check
↓
退出 maintenance
```

注意：

> v0.1 如果没有稳定 Release 机制，可以先做命令框架，不要伪造版本更新逻辑。

---

# 25. 安全约束

必须遵守：

```text
[ ] 应用数据库禁止 root
[ ] 敏感配置 chmod 600
[ ] 不使用 chmod -R 777
[ ] Shell 命令失败不能静默忽略
[ ] 下载远程代码必须使用 HTTPS
[ ] 避免把密码输出到日志
[ ] Setup Token 只能使用一次
[ ] Nginx 配置修改前做好验证
[ ] nginx -t 通过后才 reload
[ ] 数据库迁移使用 --force 仅限明确生产流程
```

建议 Shell 开头：

```bash
set -Eeuo pipefail
```

但必须结合错误处理，避免因为预期允许失败的探测命令导致整个 Installer 退出。

---

# 26. Shell 编码规范

建议：

```text
- Bash
- shellcheck 尽量通过
- 函数 snake_case
- 常量 UPPER_CASE
- 路径统一定义为变量
- 所有关键命令检查 exit code
- 不依赖当前工作目录
- 所有模板通过固定路径读取
- 不在函数内部无理由改变全局 cwd
- 避免复制重复逻辑
```

例如：

```bash
readonly CDSI_CONFIG_DIR="/etc/cdsi"
readonly CDSI_APP_DIR="/var/www/cdsi"
readonly CDSI_LOG_FILE="/var/log/cdsi/install.log"
```

---

# 27. 配置与源码边界

Installer 负责：

```text
操作系统环境
服务安装
服务配置
CDSI Core 部署
CDSI .env 写入
域名
HTTPS
进程管理
健康检查
```

CDSI Core 负责：

```text
业务逻辑
用户系统
Creator Assets
文章
观点
视频
Podcast
Audience
Distribution
Data
Action
```

不要把业务逻辑塞入 Installer。

---

# 28. 第一阶段开发顺序

严格按里程碑推进。

## Milestone 1 — Installer Skeleton

```text
[ ] install.sh
[ ] lib/common.sh
[ ] lib/logger.sh
[ ] scripts/check-env.sh
[ ] 基础错误处理
[ ] 安装状态输出
```

验收：

```text
在裸 Ubuntu 上执行 Installer，
能够完成系统检查并正确输出结果。
```

---

## Milestone 2 — Nginx + PHP + MySQL

```text
[ ] Nginx 模块
[ ] PHP 模块
[ ] Composer
[ ] MySQL 模块
[ ] Secrets
[ ] Config
```

验收：

```text
裸服务器运行 Installer 后：
Nginx / PHP-FPM / MySQL 正常，
CDSI 数据库和应用用户正常建立。
```

---

## Milestone 3 — Redis + Supervisor

```text
[ ] Redis
[ ] Supervisor
[ ] Queue Worker 模板
[ ] 服务 enable
```

验收：

```text
服务器 reboot 后组件自动恢复。
```

---

## Milestone 4 — CDSI Core Deploy

```text
[ ] /var/www/cdsi
[ ] composer install
[ ] .env
[ ] APP_KEY
[ ] migration
[ ] storage link
[ ] permissions
[ ] application verify
```

验收：

```text
服务器本机可以通过 HTTP 打开 CDSI。
```

---

## Milestone 5 — Domain + SSL

```text
[ ] Domain input
[ ] DNS check
[ ] Nginx server_name
[ ] Certbot
[ ] HTTPS
```

验收：

```text
https://creator.example.com
正常访问。
```

---

## Milestone 6 — CDSI CLI

```text
[ ] cdsi version
[ ] cdsi status
[ ] cdsi doctor
[ ] /usr/local/bin/cdsi
```

---

## Milestone 7 — Idempotency / Error Handling

```text
[ ] 第二次安装
[ ] 已安装组件识别
[ ] 部分失败恢复
[ ] 日志
[ ] exit code
[ ] 不破坏现有数据
```

---

## Milestone 8 — Fresh Server Integration Test

必须使用全新 VPS / VM 完整验证。

---

# 29. 集成测试场景

## Test 01 — 全新服务器

```text
Given:
全新 Ubuntu Server

When:
运行 CDSI Installer

Then:
CDSI 可通过 HTTPS 访问
```

---

## Test 02 — 无手工配置

整个过程不允许：

```text
vim /etc/nginx/...
vim /etc/php/...
mysql -u root ...
```

作为必要安装步骤。

---

## Test 03 — 重复安装

连续运行两次：

```bash
sudo ./install.sh
sudo ./install.sh
```

第二次不得破坏第一次结果。

---

## Test 04 — Doctor

```bash
cdsi doctor
```

所有必要组件状态正确。

---

## Test 05 — Reboot

```bash
reboot
```

回来后：

```text
Nginx       Running
PHP-FPM     Running
MySQL       Running
Redis       Running
Supervisor  Running
Queue       Running
CDSI        Available
```

---

## Test 06 — DNS 未配置

安装时 DNS 尚未指向服务器：

```text
CDSI Core 安装成功
HTTP 本地环境可用
SSL 标记 Pending
Installer 不整体失败
```

---

## Test 07 — 某组件已存在

例如服务器已有 Nginx：

```text
Installer 能识别
不盲目覆盖
配置 CDSI site
验证最终状态
```

---

# 30. Codex 执行要求

Codex 实现时遵循以下规则：

1. **先阅读现有仓库结构和 AGENTS.md。**
2. 不擅自重构 CDSI Core。
3. 本阶段聚焦 M0 / Installer。
4. 每个 Milestone 单独实现、单独测试。
5. 不一次生成一个巨大 installer。
6. 新增 Shell 文件必须职责单一。
7. 所有操作尽量幂等。
8. 不假设服务器永远是空环境。
9. 不忽略安全问题。
10. 不为了“支持更多系统”引入过度抽象。
11. 优先保证 Ubuntu 单一路径可靠。
12. 如果实际 CDSI Core 的 PHP / Laravel 依赖与本文不同，以仓库实际依赖为准，并更新 Installer。
13. 对不确定的操作先检查现有代码和系统状态，不要猜测。
14. 每完成一个 Milestone，给出：
    - 修改文件列表
    - 已完成能力
    - 测试命令
    - 已知限制
    - 下一步建议

---

# 31. 历史里程碑说明

本文最初要求只实现 Installer Skeleton、Logger、Preflight 和 Error
Handling；该里程碑已经完成，Nginx、PHP-FPM、MySQL、Certbot 和 WordPress
主流程也已实现。不得再依据旧清单禁止这些组件或从不存在的
旧版设想中的目录结构重新搭建工程。

当前最高优先级是对 `sudo ./install.sh` 进行干净服务器、重复执行、部分失败、
DNS/证书降级、升级和卸载安全验证，并实现真实健康检查。新增功能前先查阅
根目录文档中的当前状态。

---

# 32. 项目原则

CDSI Installer 不是一个附带部署脚本。

它本身就是 CDSI 数字主权基础设施的一部分。

如果用户必须理解：

```text
Linux
DNS
Nginx
PHP
MySQL
Redis
SSL
Queue
Supervisor
Deployment
```

才能拥有自己的数字节点，那么“数字主权”仍然具有很高技术门槛。

CDSI M0 的任务，就是把这些复杂度逐渐压缩到：

```bash
cdsi install
```

最终让用户完成：

```text
输入域名
↓
自动配置基础设施
↓
得到自己的 CDSI Node
```

---

# 33. M0 核心判断

> **先不要做文章、视频、Podcast、会员和用户关系。**

第一步只证明一件事：

> **一个人可以通过自动化工具，在自己的服务器和域名上建立一个完全属于自己的数字节点。**

当这一点成立后，CDSI 才真正从项目纲领进入可运行的软件阶段。
