# Grafana 可视化平台部署

使用 Ansible 自动化部署 Grafana Enterprise 版本。

## 功能特性

- 自动安装 Grafana Enterprise 12.3.0
- 自动配置 Prometheus 数据源
- 预装优化的 Node Exporter 监控仪表板
- 支持动态更新仪表板配置
- 自动配置 systemd 服务

## 前置要求

1. Ubuntu 操作系统
2. 至少 2GB RAM
3. 至少 10GB 磁盘空间
4. Prometheus 已部署 (192.168.31.80:9090)
5. Ansible 已配置并可访问目标主机

## 虚拟机配置

在 `inventory/hosts.ini` 中配置:

```ini
[grafana_cluster]
Grafana ansible_host=192.168.31.60
```

## 部署步骤

### 初次部署
```bash
ansible-playbook -i inventory/hosts.ini playbook/Grafana/deploy-grafana.yml
```

### 更新仪表板
```bash
ansible-playbook -i inventory/hosts.ini playbook/Grafana/update-dashboards.yml
```

## 配置说明

编辑 `playbook/Grafana/roles/install-grafana/defaults/main.yml`:

```yaml
grafana_version: "12.3.0"
grafana_port: 3000
grafana_admin_user: "admin"
grafana_admin_password: "admin"
grafana_domain: "192.168.31.60"

# Prometheus 数据源配置
prometheus_url: "http://192.168.31.80:9090"
```

## 访问 Grafana

### Web UI
- URL: http://192.168.31.60:3000
- 默认用户名: admin
- 默认密码: admin
- 首次登录会提示修改密码

## 预配置内容

### 数据源
- **Prometheus**: 已自动配置指向 http://192.168.31.80:9090

### 仪表板

**所有节点监控概览** - 优化的主机监控仪表板
- 监控 18 个唯一节点（无重复）
- 显示格式: 节点名称 (IP:端口)
- 实时监控指标：
  - CPU 使用率（按节点）
  - 内存使用率（按节点）
  - 磁盘使用率（按节点）
  - 网络流量（按节点）
- 统计面板：
  - 总节点数
  - 在线节点数
  - 离线节点列表（显示不在线虚拟机的名称）
  - 平均 CPU 使用率
  - 平均内存使用率

### 监控的节点列表

1. KubernetesMaster000 (192.168.31.30:9100)
2. KubernetesMaster001 (192.168.31.31:9100)
3. KubernetesWorker000-003 (192.168.31.40-43:9100)
4. GitLab (192.168.31.50:9100)
5. Grafana (192.168.31.60:9100)
6. Jenkins (192.168.31.70:9100)
7. Prometheus (192.168.31.80:9100)
8. Redis000-002 (192.168.31.90-92:9100)
9. MySQL (192.168.31.110:9100)
10. Kafka (192.168.31.120:9100)
11. RocketMQ (192.168.31.130:9100)
12. MongoDB (192.168.31.140:9100)
13. ElasticSearch (192.168.31.150:9100)

## 创建自定义仪表板

### 1. 导入社区仪表板

Grafana 支持从 https://grafana.com/grafana/dashboards/ 导入仪表板：

常用仪表板 ID:
- Node Exporter Full: 1860
- Prometheus 2.0 Stats: 3662
- Kubernetes Cluster Monitoring: 7249
- Redis Dashboard: 11835
- MySQL Overview: 7362

导入方法：
1. 点击 "+" → "Import"
2. 输入仪表板 ID
3. 选择 Prometheus 数据源
4. 点击 "Import"

### 2. 创建自定义面板

示例查询（已优化，显示节点名称和 IP）：

**CPU 使用率**：
```promql
(100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle",job="all_nodes"}[5m])) * 100)) 
* on(instance) group_left(nodename) node_uname_info{job="all_nodes"}
```
图例格式: `{{nodename}} ({{instance}})`

**内存使用率**：
```promql
((1 - (node_memory_MemAvailable_bytes{job="all_nodes"} / node_memory_MemTotal_bytes{job="all_nodes"})) * 100) 
* on(instance) group_left(nodename) node_uname_info{job="all_nodes"}
```
图例格式: `{{nodename}} ({{instance}})`

**离线节点检测**：
```promql
label_replace(up{job="all_nodes"} == 0, "nodename", "$1", "instance", "([^:]+):.*") 
* on(instance) group_left(nodename) node_uname_info{job="all_nodes"}
```
说明: 
- 查询所有 `up` 值为 0 的节点（离线节点）
- 自动提取并显示节点名称
- 如果所有节点在线，面板显示"全部在线"
- 如果有节点离线，列出所有离线节点的名称

**磁盘使用率**：
```promql
((1 - (node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs",job="all_nodes"} 
/ node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs",job="all_nodes"})) * 100) 
* on(instance) group_left(nodename) node_uname_info{job="all_nodes"}
```
图例格式: `{{nodename}} ({{instance}})`

## 告警配置

### 配置邮件告警

编辑 `/etc/grafana/grafana.ini`:

```ini
[smtp]
enabled = true
host = smtp.gmail.com:587
user = your-email@gmail.com
password = your-app-password
from_address = your-email@gmail.com
from_name = Grafana

[alerting]
enabled = true
```

重启 Grafana:
```bash
sudo systemctl restart grafana-server
```

### 创建告警规则

1. 打开仪表板面板
2. 点击 "Edit"
3. 切换到 "Alert" 标签
4. 创建告警条件
5. 配置通知渠道

## 用户管理

### 创建新用户
1. 点击左侧菜单 "Configuration" → "Users"
2. 点击 "Invite"
3. 输入邮箱和角色
4. 发送邀请

### 用户角色
- **Admin**: 完全访问权限
- **Editor**: 可以创建和编辑仪表板
- **Viewer**: 只能查看仪表板

## 数据源管理

### 添加其他数据源

Grafana 支持多种数据源：
- InfluxDB
- MySQL
- PostgreSQL
- Elasticsearch
- Loki (日志)
- Jaeger (追踪)

添加方法：
1. Configuration → Data Sources
2. Add data source
3. 选择类型并配置连接

## 备份和恢复

### 备份 Grafana 配置
```bash
# 备份数据库
sudo cp /var/lib/grafana/grafana.db /backup/grafana.db.backup

# 备份配置文件
sudo tar -czf grafana-backup-$(date +%Y%m%d).tar.gz \
  /etc/grafana \
  /var/lib/grafana \
  /usr/share/grafana
```

### 恢复 Grafana
```bash
# 停止服务
sudo systemctl stop grafana-server

# 恢复数据
sudo tar -xzf grafana-backup-YYYYMMDD.tar.gz -C /

# 启动服务
sudo systemctl start grafana-server
```

## 性能优化

### 数据库优化

如果仪表板很多，考虑迁移到 PostgreSQL：

```ini
[database]
type = postgres
host = 192.168.31.110:5432
name = grafana
user = grafana
password = grafana_password
```

### 缓存优化

编辑 `/etc/grafana/grafana.ini`:

```ini
[dataproxy]
timeout = 30
keep_alive_seconds = 30
max_idle_connections_per_host = 10
```

## 验证部署

```bash
# 检查服务状态
ansible grafana_cluster -i inventory/hosts.ini -m shell -a "systemctl status grafana-server"

# 检查版本
curl http://192.168.31.60:3000/api/health

# 测试登录
curl -X POST http://192.168.31.60:3000/api/login/ping
```

## 常见问题

### Grafana 无法访问
检查服务和防火墙：
```bash
sudo systemctl status grafana-server
sudo netstat -tlnp | grep 3000
```

### 无法连接 Prometheus
检查网络和 Prometheus 状态：
```bash
curl http://192.168.31.80:9090/api/v1/query?query=up
```

### 仪表板加载缓慢
- 减少查询时间范围
- 增加刷新间隔
- 优化 PromQL 查询

## 插件管理

### 安装插件
```bash
# 列出可用插件
sudo grafana-cli plugins list-remote

# 安装插件
sudo grafana-cli plugins install <plugin-id>

# 重启 Grafana
sudo systemctl restart grafana-server
```

### 常用插件
- grafana-piechart-panel: 饼图
- grafana-clock-panel: 时钟
- grafana-worldmap-panel: 世界地图

## 卸载

```bash
# 停止服务
sudo systemctl stop grafana-server
sudo systemctl disable grafana-server

# 删除软件包
sudo apt remove --purge grafana-enterprise

# 删除数据
sudo rm -rf /var/lib/grafana /etc/grafana

# 删除用户
sudo userdel grafana
sudo groupdel grafana
```

## 升级 Grafana

```bash
# 备份数据
sudo systemctl stop grafana-server
sudo cp -r /var/lib/grafana /var/lib/grafana.backup

# 更新软件包
sudo apt update
sudo apt upgrade grafana-enterprise

# 启动服务
sudo systemctl start grafana-server
```
