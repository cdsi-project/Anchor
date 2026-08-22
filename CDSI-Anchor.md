# CDSI Anchor

## 个人数字主权，从一个脚本开始

CDSI Anchor 是 CDSI（Creator Digital Sovereignty Infrastructure）的
服务器基础设施安装工具，它把一台受支持的服务器配置为可访问的 OpenWeb(WordPress)
节点。

> 当前状态：M0 集成与加固，Installer v0.3.0。

## 当前实现

默认安装流程已经实现：

- 用户只需执行简单交互，即可快速配置Linux服务器环境
- 安装 Nginx、MySQL、PHP、Wordpress等开源软件，无需额外付费
- 自动配置 WordPress 作为 OpenWeb站点，自动配置HTTPS
- 自动创建 WordPress 管理员和 [CDSI Beacon](https://github.com/cdsi-project/Beacon) 自动发布文章API

当前默认组件：

| 组件 | 入口 | 状态 |
| --- | --- | --- |
| Nginx | `scripts/install-nginx.sh` | 默认安装 |
| MySQL | `scripts/install-mysql.sh` | 默认安装 |
| PHP-FPM | `scripts/install-php.sh` | 默认安装 |
| Certbot | `scripts/install-certbot.sh` | 默认安装 |
| WordPress | `scripts/install-wordpress.sh` | 默认安装 |
| Redis | `scripts/install-redis.sh` | 需要时可单独安装 |
| Supervisor | `scripts/install-supervisor.sh` | 需要时可单独安装 |

## 安装

支持 Ubuntu Server 24.04 LTS 和 26.04 LTS。主安装器需要 root/sudo 权限和
交互式终端：

```bash
git clone https://github.com/cdsi-project/Anchor.git
cd Anchor
sudo ./install.sh
```

`install.sh` 是统一入口。`scripts/` 中的脚本也可独立运行

完整菜单、域名/SSL 配置、凭据位置、卸载风险和排错步骤见
[INSTALL.md](INSTALL.md)。

## 安装结果

“安装全部”完成后，终端会显示：

```text
网站地址
WordPress 后台地址
WordPress 登录用户和密码
CDSI Beacon 源站域名、用户名和 Application Password
```

凭据保存在仓库本机的 `password/` 目录并设置为 600 权限；
Application Password 只在创建时返回，丢失后可在wordpress后台重新生成

## 产品边界

Anchor 当前负责基础设施和 WordPress OpenWeb 节点的安装，不负责本地资产
扫描、云对象存储备份或桌面内容管理。这些本地工作流由 [CDSI Beacon](https://github.com/cdsi-project/Beacon) 负责。

WordPress 自身提供文章管理、RSS 和 REST API；

Anchor 可以运行在提供兼容 Ubuntu Server 的云服务器或自有主机上，但项目
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

1. 在两种受支持的 Ubuntu LTS 上完成干净服务器回归测试。
2. 验证重复安装、部分失败后重跑和系统重启。
3. 加固 DNS、证书、网络和软件包锁异常的恢复路径。
4. 验证升级兼容、卸载范围和数据恢复方案。
5. 用真实检查替换健康脚本占位实现。

后续阶段只有在根目录 [README.md](README.md) 与 [AGENTS.md](AGENTS.md)
明确调整路线后才启动，历史设计稿不能作为当前实现状态。

## 设计原则

- 使用系统默认软件源，避免对第三方仓库形成隐式依赖。
- 安装脚本默认幂等，不重置已有凭据或覆盖用户数据。
- 任何删除、覆盖或凭据轮换都必须显式确认并可审计。
- 用户拥有域名、数据库、内容、配置和备份；CDSI 不形成新的数据孤岛。

CDSI Anchor 的目标不是隐藏风险，而是把可验证、可恢复的基础设施操作压缩为
一个清晰入口，让创作者更容易拥有自己的 OpenWeb 原点。
