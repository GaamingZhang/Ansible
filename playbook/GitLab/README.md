# GitLab Ansible Playbook

使用 Ansible 自动化在 Ubuntu 虚拟机上安装 GitLab CE。

## 功能特性

- 自动安装 GitLab CE (Community Edition)
- 配置 GitLab 外部访问 URL
- 自动配置邮件服务器 (Postfix)
- 支持自定义配置选项
- 支持代理环境
- 性能优化选项（适合内存受限环境）

## 前置要求

1. Ubuntu 24.04 虚拟机
2. 至少 4GB RAM（推荐 8GB）
3. 至少 20GB 磁盘空间
4. 虚拟机可通过代理访问互联网 (http://192.168.31.132:20171)
5. Ansible 已配置并可访问目标主机

## 虚拟机配置

在 `inventory/hosts.ini` 中配置 GitLab 主机:

```ini
[gitLab_cluster]
GitLab ansible_host=192.168.31.50
```

## 配置

编辑 `roles/install-gitlab/defaults/main.yml` 修改配置:

### 关键配置项

```yaml
# GitLab 版本
gitlab_version: "17.6.1-ce.0"

# 访问 URL
gitlab_external_url: "http://192.168.31.50"

# 端口配置
gitlab_http_port: 80
gitlab_ssh_port: 22

# 性能优化（内存受限环境）
gitlab_reduce_memory: true

# 功能开关
gitlab_registry_enabled: false
gitlab_pages_enabled: false
```

### 代理配置（如果需要）

```yaml
http_proxy: "http://192.168.31.132:20171"
https_proxy: "http://192.168.31.132:20171"
no_proxy: "localhost,127.0.0.1,192.168.31.0/24"
```

## 部署

### 基本部署

```bash
cd /home/node/ansible
ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml
```

### 使用自定义配置

```bash
ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml \
  -e "gitlab_external_url=http://192.168.31.50" \
  -e "gitlab_reduce_memory=true"
```

## 访问 GitLab

部署完成后，使用以下信息访问:

1. **访问地址**: http://192.168.31.50
2. **用户名**: root
3. **初始密码**: 查看 playbook 输出或执行以下命令:

```bash
ssh node@192.168.31.50 "sudo cat /etc/gitlab/initial_root_password"
```

**重要**: 初始密码文件将在 24 小时后自动删除，请及时登录并修改密码！

## 首次登录

1. 访问 http://192.168.31.50
2. 使用用户名 `root` 和初始密码登录
3. 立即修改密码（用户设置 -> 密码）
4. 配置个人资料和邮箱

## 验证安装

```bash
# 检查 GitLab 服务状态
ssh node@192.168.31.50 "sudo gitlab-ctl status"

# 查看 GitLab 版本
ssh node@192.168.31.50 "sudo gitlab-rake gitlab:env:info"

# 检查系统健康状态
ssh node@192.168.31.50 "sudo gitlab-rake gitlab:check"
```

## 常用管理命令

### 服务管理

```bash
# 查看所有服务状态
sudo gitlab-ctl status

# 启动所有服务
sudo gitlab-ctl start

# 停止所有服务
sudo gitlab-ctl stop

# 重启所有服务
sudo gitlab-ctl restart

# 重新配置 GitLab
sudo gitlab-ctl reconfigure
```

### 日志查看

```bash
# 查看所有日志
sudo gitlab-ctl tail

# 查看特定服务日志
sudo gitlab-ctl tail nginx
sudo gitlab-ctl tail postgresql
sudo gitlab-ctl tail redis
```

## 备份与恢复

### 创建备份

```bash
# 手动备份
sudo gitlab-backup create

# 备份文件位于: /var/opt/gitlab/backups/
```

### 恢复备份

```bash
# 停止服务
sudo gitlab-ctl stop puma
sudo gitlab-ctl stop sidekiq

# 恢复备份（替换 BACKUP_TIMESTAMP 为实际时间戳）
sudo gitlab-backup restore BACKUP=BACKUP_TIMESTAMP

# 重启服务
sudo gitlab-ctl restart
sudo gitlab-rake gitlab:check SANITIZE=true
```

### 配置自动备份

编辑 `/etc/gitlab/gitlab.rb`:

```ruby
# 每天凌晨 2 点备份
gitlab_rails['backup_keep_time'] = 604800  # 保留 7 天
```

然后重新配置:
```bash
sudo gitlab-ctl reconfigure
```

## SSH 克隆配置

### 使用默认端口 (22)

```bash
git clone git@192.168.31.50:username/project.git
```

### 使用自定义端口

如果修改了 SSH 端口，在 `~/.ssh/config` 中添加:

```
Host gitlab.example.com
    Hostname 192.168.31.50
    Port 2222
    User git
```

## Email 配置

### 启用 SMTP

编辑 `roles/install-gitlab/defaults/main.yml`:

```yaml
gitlab_email_enabled: true
gitlab_email_from: "gitlab@example.com"

gitlab_smtp_address: "smtp.example.com"
gitlab_smtp_port: 587
gitlab_smtp_user: "gitlab@example.com"
gitlab_smtp_password: "your_password"
gitlab_smtp_domain: "example.com"
```

重新运行 playbook 或手动配置:

```bash
# 编辑配置
sudo vim /etc/gitlab/gitlab.rb

# 重新配置
sudo gitlab-ctl reconfigure

# 测试邮件
sudo gitlab-rails console
Notify.test_email('admin@example.com', 'Test', 'Test email').deliver_now
```

## HTTPS 配置

### 使用 Let's Encrypt

```yaml
gitlab_external_url: "https://gitlab.example.com"
```

### 使用自签名证书

```bash
# 生成证书
sudo mkdir -p /etc/gitlab/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/gitlab/ssl/gitlab.key \
  -out /etc/gitlab/ssl/gitlab.crt

# 配置
gitlab_https_enabled: true
gitlab_ssl_certificate: "/etc/gitlab/ssl/gitlab.crt"
gitlab_ssl_certificate_key: "/etc/gitlab/ssl/gitlab.key"
```

## 性能优化

### 内存受限环境（4GB RAM）

```yaml
gitlab_reduce_memory: true
```

这将:
- 减少 Puma 工作进程数
- 降低 Sidekiq 并发数
- 禁用 Prometheus 监控
- 禁用 Grafana

### 禁用不需要的功能

```yaml
gitlab_registry_enabled: false  # Container Registry
gitlab_pages_enabled: false     # GitLab Pages
```

## 故障排查

### GitLab 无法访问

```bash
# 检查服务状态
sudo gitlab-ctl status

# 查看 nginx 日志
sudo gitlab-ctl tail nginx

# 检查端口监听
sudo netstat -tlnp | grep 80
```

### 内存不足

```bash
# 查看内存使用
free -h

# 启用 swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 502 错误

```bash
# 检查 Puma 状态
sudo gitlab-ctl status puma

# 重启 Puma
sudo gitlab-ctl restart puma

# 查看日志
sudo gitlab-ctl tail puma
```

### 磁盘空间不足

```bash
# 检查磁盘使用
df -h

# 清理旧的 artifacts
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files

# 清理旧备份
sudo find /var/opt/gitlab/backups -type f -mtime +7 -delete
```

## 升级 GitLab

```bash
# 备份当前版本
sudo gitlab-backup create

# 更新包列表
sudo apt update

# 升级 GitLab
sudo apt install gitlab-ce

# 重新配置
sudo gitlab-ctl reconfigure
```

## 卸载

```bash
# 停止服务
sudo gitlab-ctl stop

# 卸载包
sudo apt purge gitlab-ce

# 删除数据（可选）
sudo rm -rf /opt/gitlab /var/opt/gitlab /etc/gitlab
```

**注意**: 这将删除所有 GitLab 数据！请先备份！

## 目录结构

```
GitLab/
├── deploy-gitlab.yml              # 主 playbook
├── roles/
│   └── install-gitlab/
│       ├── defaults/
│       │   └── main.yml          # 默认变量
│       ├── tasks/
│       │   └── main.yml          # 安装任务
│       └── templates/
│           └── gitlab.rb.j2       # GitLab 配置模板
└── README.md                      # 本文件
```

## 重要文件路径

- 配置文件: `/etc/gitlab/gitlab.rb`
- 数据目录: `/var/opt/gitlab/`
- 日志目录: `/var/log/gitlab/`
- 备份目录: `/var/opt/gitlab/backups/`
- Git 数据: `/var/opt/gitlab/git-data/`

## 参考资源

- [GitLab 官方文档](https://docs.gitlab.com/)
- [GitLab 安装指南](https://about.gitlab.com/install/)
- [GitLab 配置选项](https://docs.gitlab.com/omnibus/settings/)
- [GitLab 备份恢复](https://docs.gitlab.com/ee/raketasks/backup_restore.html)
