# Jenkins Ansible Playbook

使用 Ansible 自动化在 Ubuntu 虚拟机上安装 Jenkins。

## 功能特性

- 自动安装 Jenkins LTS 2.528.2 版本
- 自动安装并配置 Java 17
- 配置 Jenkins 服务和端口
- 支持代理环境
- 自动启动并设置开机自启

## 前置要求

1. Ubuntu 24.04 虚拟机
2. 至少 2GB RAM（推荐 4GB）
3. 至少 10GB 磁盘空间
4. 虚拟机可通过代理访问互联网 (http://192.168.31.132:20171)
5. Ansible 已配置并可访问目标主机

## 虚拟机配置

在 `inventory/hosts.ini` 中配置 Jenkins 主机:

```ini
[jenkins_cluster]
Jenkins ansible_host=192.168.31.70
```

## 配置

编辑 `roles/install-jenkins/defaults/main.yml` 修改配置:

### 关键配置项

```yaml
# Jenkins 版本
jenkins_version: "2.528.2"  # LTS 版本

# Java 版本
java_version: "openjdk-17-jre"

# Jenkins 端口
jenkins_http_port: 8080

# Java 内存配置
jenkins_java_options: "-Djava.awt.headless=true -Xmx2g -Xms512m"
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
ansible-playbook -i inventory/hosts.ini playbook/Jenkins/deploy-jenkins.yml
```

### 使用自定义配置

```bash
ansible-playbook -i inventory/hosts.ini playbook/Jenkins/deploy-jenkins.yml \
  -e "jenkins_http_port=8080" \
  -e "jenkins_java_options='-Xmx4g'"
```

## 访问 Jenkins

部署完成后，使用以下信息访问:

1. **访问地址**: http://192.168.31.70:8080
2. **初始管理员密码**: 查看 playbook 输出或执行以下命令:

```bash
ssh node@192.168.31.70 "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
```

## 首次设置

1. 访问 http://192.168.31.70:8080
2. 输入初始管理员密码解锁 Jenkins
3. 选择"安装推荐的插件"或"选择要安装的插件"
4. 创建第一个管理员用户
5. 配置 Jenkins URL
6. 开始使用 Jenkins！

## 验证安装

```bash
# 检查 Jenkins 服务状态
ssh node@192.168.31.70 "sudo systemctl status jenkins"

# 检查 Jenkins 版本
ssh node@192.168.31.70 "java -jar /usr/share/java/jenkins.war --version"

# 查看 Jenkins 日志
ssh node@192.168.31.70 "sudo journalctl -u jenkins -n 50"
```

## 常用管理命令

### 服务管理

```bash
# 查看服务状态
sudo systemctl status jenkins

# 启动服务
sudo systemctl start jenkins

# 停止服务
sudo systemctl stop jenkins

# 重启服务
sudo systemctl restart jenkins

# 重新加载配置
sudo systemctl reload jenkins
```

### 日志查看

```bash
# 查看实时日志
sudo journalctl -u jenkins -f

# 查看最近日志
sudo journalctl -u jenkins -n 100

# 查看 Jenkins 自身日志
sudo tail -f /var/log/jenkins/jenkins.log
```

## 配置管理

### Jenkins 配置文件位置

- 主配置: `/etc/default/jenkins`
- systemd 覆盖: `/etc/systemd/system/jenkins.service.d/override.conf`
- Jenkins 主目录: `/var/lib/jenkins`
- 日志目录: `/var/log/jenkins`

### 修改配置

```bash
# 编辑 Jenkins 配置
sudo vim /etc/default/jenkins

# 重新加载 systemd
sudo systemctl daemon-reload

# 重启 Jenkins
sudo systemctl restart jenkins
```

## 备份与恢复

### 备份

```bash
# 备份 Jenkins 主目录
sudo tar -czf jenkins-backup-$(date +%Y%m%d).tar.gz -C /var/lib jenkins

# 备份到远程位置
scp jenkins-backup-*.tar.gz user@backup-server:/backups/
```

### 恢复

```bash
# 停止 Jenkins
sudo systemctl stop jenkins

# 恢复备份
sudo tar -xzf jenkins-backup-YYYYMMDD.tar.gz -C /var/lib

# 修正权限
sudo chown -R jenkins:jenkins /var/lib/jenkins

# 启动 Jenkins
sudo systemctl start jenkins
```

## 插件管理

### 通过 CLI 安装插件

```bash
# 下载 Jenkins CLI
wget http://192.168.31.70:8080/jnlpJars/jenkins-cli.jar

# 安装插件
java -jar jenkins-cli.jar -s http://192.168.31.70:8080/ \
  -auth admin:password install-plugin git workflow-aggregator
```

### 推荐插件

- **git**: Git 版本控制
- **workflow-aggregator**: Pipeline 支持
- **docker-workflow**: Docker 集成
- **kubernetes**: Kubernetes 集成
- **configuration-as-code**: JCasC 配置即代码
- **blueocean**: 现代化 UI

## 集成配置

### 与 GitLab 集成

1. 安装 GitLab 插件
2. 在 Jenkins 中配置 GitLab 连接
3. 在 GitLab 项目中配置 Webhook

### 与 Kubernetes 集成

1. 安装 Kubernetes 插件
2. 配置 Kubernetes Cloud
3. 使用 Pod 模板运行构建

### 与 Docker 集成

```bash
# 添加 jenkins 用户到 docker 组
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

## 性能优化

### 增加内存

编辑 `/etc/default/jenkins`:

```bash
JAVA_ARGS="-Djava.awt.headless=true -Xmx4g -Xms1g"
```

### 启用 JVM 性能选项

```bash
JAVA_ARGS="$JAVA_ARGS -XX:+UseG1GC -XX:+DisableExplicitGC"
```

## 安全配置

### 启用 CSRF 保护

在 Jenkins 配置中启用 CSRF 保护（默认已启用）

### 配置用户权限

使用基于角色的访问控制（RBAC）插件

### 启用 HTTPS

使用 Nginx 反向代理配置 HTTPS:

```nginx
server {
    listen 443 ssl;
    server_name jenkins.example.com;
    
    ssl_certificate /etc/ssl/certs/jenkins.crt;
    ssl_certificate_key /etc/ssl/private/jenkins.key;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 故障排查

### Jenkins 无法启动

```bash
# 检查端口占用
sudo netstat -tlnp | grep 8080

# 查看详细日志
sudo journalctl -u jenkins -xe

# 检查 Java 版本
java -version
```

### 内存不足

```bash
# 检查内存使用
free -h

# 降低 Java 堆大小
# 编辑 /etc/default/jenkins
JAVA_ARGS="-Xmx1g -Xms512m"
```

### 插件安装失败

```bash
# 检查代理配置
cat /etc/default/jenkins | grep -i proxy

# 手动下载插件
wget https://updates.jenkins.io/download/plugins/git/latest/git.hpi
sudo cp git.hpi /var/lib/jenkins/plugins/
sudo chown jenkins:jenkins /var/lib/jenkins/plugins/git.hpi
sudo systemctl restart jenkins
```

## 升级 Jenkins

```bash
# 备份
sudo tar -czf jenkins-backup-$(date +%Y%m%d).tar.gz -C /var/lib jenkins

# 更新包列表
sudo apt update

# 升级 Jenkins
sudo apt install jenkins

# 重启服务
sudo systemctl restart jenkins
```

## 卸载

```bash
# 停止服务
sudo systemctl stop jenkins
sudo systemctl disable jenkins

# 卸载包
sudo apt purge jenkins

# 删除数据（可选）
sudo rm -rf /var/lib/jenkins /etc/default/jenkins
```

**注意**: 这将删除所有 Jenkins 数据！请先备份！

## 目录结构

```
Jenkins/
├── deploy-jenkins.yml              # 主 playbook
├── roles/
│   └── install-jenkins/
│       ├── defaults/
│       │   └── main.yml           # 默认变量
│       ├── tasks/
│       │   └── main.yml           # 安装任务
│       └── templates/
│           ├── jenkins-defaults.j2
│           └── jenkins-service-override.conf.j2
└── README.md                       # 本文件
```

## 重要文件路径

- 配置文件: `/etc/default/jenkins`
- systemd 配置: `/etc/systemd/system/jenkins.service.d/override.conf`
- 主目录: `/var/lib/jenkins`
- 日志目录: `/var/log/jenkins`
- 初始密码: `/var/lib/jenkins/secrets/initialAdminPassword`

## 参考资源

- [Jenkins 官方文档](https://www.jenkins.io/doc/)
- [Jenkins 安装指南](https://www.jenkins.io/doc/book/installing/)
- [Jenkins 插件中心](https://plugins.jenkins.io/)
- [Jenkins Pipeline 文档](https://www.jenkins.io/doc/book/pipeline/)
