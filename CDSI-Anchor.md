# CDSI Anchor

## 个人数字主权，从一个脚本开始

CDSI Anchor 是 CDSI（Creator Digital Sovereignty Infrastructure）的
服务器基础设施安装工具，它把一台受支持的服务器配置为可访问的 OpenWeb(WordPress)
节点。

> 当前状态：M0 集成与加固，Installer v0.3.0。

## 当前实现

默认安装流程已经实现：

- 用户只需执行简单交互，即可快速配置Linux服务器环境
- 安装 Nginx、MySQL/MariaDB、PHP、Wordpress等开源软件，无需额外付费
- 自动配置 WordPress 作为 OpenWeb 站点；域名验证通过后配置 HTTPS
- 没有域名时保持 `http://<服务器 IP>`，后续可独立配置域名或显式尝试 IP HTTPS
- 自动创建 WordPress 管理员和 [CDSI Beacon](https://github.com/cdsi-project/Beacon) 自动发布文章API

当前默认组件：

| 组件 | 入口 | 状态 |
| --- | --- | --- |
| Nginx | `scripts/install-nginx.sh` | 默认安装 |
| MySQL/MariaDB | `scripts/install-mysql.sh` | 默认安装，按平台选择系统包 |
| PHP-FPM | `scripts/install-php.sh` | 默认安装 |
| Certbot | `scripts/install-certbot.sh` | 默认安装 |
| WordPress | `scripts/install-wordpress.sh` | 默认安装 |
| Redis | `scripts/install-redis.sh` | 需要时可单独安装 |
| Supervisor | `scripts/install-supervisor.sh` | 需要时可单独安装 |

## 安装

支持 Ubuntu Server 24.04/26.04 LTS、Debian 13 和 CentOS Stream 10。主安装器
需要 root/sudo 权限和交互式终端。新服务器无需预装 Git，国内服务器可使用：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://gitee.com/cdsi/anchor/raw/v0.3.0/bootstrap.sh \
  -o anchor-bootstrap.sh && sh anchor-bootstrap.sh
```

根目录 `bootstrap.sh` 会刷新系统默认源的元数据，安装 Git、Bash、curl、CA
证书和 coreutils，优先从 Gitee、失败后从 GitHub 获取 `v0.3.0` 发布标签，
然后进入 `install.sh`。它不会改写软件源或执行全系统升级。

已有 Git 时也可手动克隆：

```bash
git clone https://gitee.com/cdsi/anchor.git Anchor
cd Anchor
sudo ./install.sh
```

`install.sh` 是统一入口。`scripts/` 中的脚本也可独立运行

公开组件脚本会检测操作系统并进入对应平台目录。Ubuntu、Debian 13 与 CentOS
Stream 10 路由均已实现；Redis 与 Supervisor 独立脚本仍仅支持 Ubuntu。

Debian 13 使用系统默认源 `default-mysql-server` 提供的 MariaDB 11.8
（MySQL-compatible），以及 PHP 8.4 和 Certbot 4.0。

完整菜单、域名/SSL 配置、凭据位置、卸载风险和排错步骤见
[INSTALL.md](INSTALL.md)。

域名和 HTTPS 不需要重装基础服务，可以独立操作：

```bash
sudo bash scripts/configure-domain.sh example.com
sudo bash scripts/configure-domain.sh --clear
sudo bash scripts/configure-https.sh example.com
sudo bash scripts/configure-https.sh --ip
```

新域名只有在所有 A 记录严格指向服务器公网 IPv4，且所有现存 AAAA 记录都
属于本服务器时才会激活。解析未就绪时只保存到 `config/domain.pending`，不会
修改当前 WordPress URL 或 Nginx 站点。

IP 公信 HTTPS 需要公网 IPv4、系统 Certbot 5.4+ 和 Let's Encrypt
`shortlived` profile；能力不足时保持 HTTP。Anchor 不承诺 CentOS Stream 10
当前 EPEL Certbot 一定支持 IP 证书。Debian 13 的默认 Certbot 4.0 支持域名
HTTPS，但不满足 IP 证书能力要求。

可通过 `CDSI_ACME_FALLBACK_SERVER` 指定备用 CA，但只在主 ACME directory
网络不可达时使用。DNS、CAA、授权、证书校验和限额错误不会自动切换；ZeroSSL
还必须提供 `CDSI_ACME_FALLBACK_EAB_KID` 与
`CDSI_ACME_FALLBACK_EAB_HMAC_KEY`。

## 安装结果

“安装全部”完成后，终端会显示：

```text
网站地址
WordPress 后台地址
WordPress 登录用户和密码
CDSI Beacon 源站域名、用户名和 Application Password
```

没有活动域名时，网站地址显示为 `http://<服务器 IP>`。报告同时区分服务的
Runtime 与 Boot 状态：Nginx、MySQL/MariaDB 和 PHP-FPM 必须同时
active/enabled；
HTTPS 配置成功时 Certbot 续期 timer 也必须 active/enabled。

凭据保存在仓库本机的 `password/` 目录并设置为 600 权限；
Application Password 只在创建时返回，丢失后可在wordpress后台重新生成

## 产品边界

Anchor 当前负责基础设施和 WordPress OpenWeb 节点的安装，不负责本地资产
扫描、云对象存储备份或桌面内容管理。这些本地工作流由 [CDSI Beacon](https://github.com/cdsi-project/Beacon) 负责。

WordPress 自身提供文章管理、RSS 和 REST API；

Anchor 可以运行在提供受支持 Ubuntu Server、Debian 或 CentOS Stream 的
云服务器或自有主机上，但项目
当前按操作系统版本验证安装路径，不对阿里云、腾讯云、AWS 等厂商分别作兼容
认证，也不会调用云厂商专有 API。

## 尚未实现

- Composer 和 CDSI Core 部署
- `cdsi install/status/doctor/update` CLI
- 真实的端到端健康检查（`scripts/health.sh` 当前是占位实现）
- 断点续装与完整的服务器备份/恢复
- CDSI 服务端 API、资产同步和数据同步配置
- 仓库内自动化的干净服务器、重装、重启和灾难恢复整机测试

## 当前优先级

M0 接下来聚焦：

1. 在所有受支持操作系统路由上完成干净服务器回归测试。
2. 验证重复安装、部分失败后重跑和系统重启。
3. 加固 DNS、证书、网络和软件包锁异常的恢复路径。
4. 验证升级兼容、卸载范围和数据恢复方案。
5. 用真实检查替换健康脚本占位实现。

后续阶段只有在根目录 [README.md](README.md) 与 [AGENTS.md](AGENTS.md)
明确调整路线后才启动，历史设计稿不能作为当前实现状态。

## 设计原则

- 基础栈使用系统默认软件源；CentOS 仅为 Certbot 显式启用 EPEL，不引入
  Remi。PHP 图片处理使用 GD，不安装 Imagick。
- 安装脚本默认幂等，不重置已有凭据或覆盖用户数据。
- 域名解析未确认、IP 证书能力不足或证书签发失败时保留可用的 HTTP 站点。
- Nginx、MySQL/MariaDB、PHP-FPM 和已配置证书的续期 timer 都验证运行与
  开机自启。
- 任何删除、覆盖或凭据轮换都必须显式确认并可审计。
- 用户拥有域名、数据库、内容、配置和备份；CDSI 不形成新的数据孤岛。

CDSI Anchor 的目标不是隐藏风险，而是把可验证、可恢复的基础设施操作压缩为
一个清晰入口，让创作者更容易拥有自己的 OpenWeb 原点。
