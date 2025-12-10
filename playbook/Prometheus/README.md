# Prometheus 监控系统部署

使用 Ansible 自动化部署 Prometheus 监控系统和 Node Exporter。

## 功能特性

- 自动安装 Prometheus 3.8.0
- 自动安装 Node Exporter 1.10.2 到所有节点
- 自动配置监控目标
- 支持动态更新配置
- 自动配置 systemd 服务

## 前置要求

1. Ubuntu 操作系统
2. 至少 2GB RAM
3. 至少 10GB 磁盘空间
4. Ansible 已配置并可访问目标主机

## 虚拟机配置

在 `inventory/hosts.ini` 中配置:

```ini
[prometheus_cluster]
Prometheus ansible_host=192.168.31.80

[allNodes:children]
kubernetes_cluster
gitLab_cluster
grafana_cluster
jenkins_cluster
prometheus_cluster
redis_cluster
mysql_cluster
kafka_cluster
rocketmq_cluster
MongoDB_cluster
ElasticSearch_cluster
```

## 部署步骤

### 1. 部署 Prometheus
```bash
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml
```

### 2. 在所有节点上部署 Node Exporter
```bash
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-node-exporter-all.yml
```

### 3. 更新 Prometheus 配置
```bash
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/update-prometheus-config.yml
```

## 配置说明

### Prometheus 配置

编辑 `playbook/Prometheus/roles/install-prometheus/defaults/main.yml`:

```yaml
prometheus_version: "3.8.0"
prometheus_port: 9090
prometheus_data_retention: "15d"
prometheus_storage_path: "/var/lib/prometheus"
```

### Node Exporter 配置

编辑 `playbook/Prometheus/roles/install-node-exporter/defaults/main.yml`:

```yaml
node_exporter_version: "1.10.2"
node_exporter_port: 9100
```

## 监控目标

当前配置监控 **18 个节点** (通过 all_nodes job 去重)：

### 基础设施 (10 个节点)
- **Kubernetes Masters** (2): 192.168.31.30-31:9100
- **Kubernetes Workers** (4): 192.168.31.40-43:9100
- **GitLab**: 192.168.31.50:9100
- **Grafana**: 192.168.31.60:9100
- **Jenkins**: 192.168.31.70:9100
- **Prometheus**: 192.168.31.80:9100

### 数据存储 (8 个节点)
- **Redis Cluster** (3): 192.168.31.90-92:9100
- **MySQL**: 192.168.31.110:9100
- **Kafka**: 192.168.31.120:9100
- **RocketMQ**: 192.168.31.130:9100
- **MongoDB**: 192.168.31.140:9100
- **ElasticSearch**: 192.168.31.150:9100

### 监控任务组 (14 个 jobs)
1. `prometheus` - Prometheus 自身
2. `kubernetes_masters` - K8s 主节点
3. `kubernetes_workers` - K8s 工作节点
4. `gitlab` - GitLab 服务器
5. `grafana` - Grafana 服务器
6. `jenkins` - Jenkins 服务器
7. `prometheus_server` - Prometheus 节点
8. `redis_cluster` - Redis 集群
9. `mysql` - MySQL 数据库
10. `kafka` - Kafka 消息队列
11. `rocketmq` - RocketMQ 消息队列
12. `mongodb` - MongoDB 数据库
13. `elasticsearch` - ElasticSearch 搜索引擎
14. `all_nodes` - 所有节点汇总（18 个唯一节点）

## 访问 Prometheus

### Web UI
- URL: http://192.168.31.80:9090
- 无需认证

### 常用查询

#### 查看所有目标状态
```promql
up
```

#### CPU 使用率
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

#### 内存使用率
```promql
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

#### 磁盘使用率
```promql
100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})
```

#### 网络流量
```promql
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])
```

## 验证部署

### 检查 Prometheus 状态
```bash
# 检查服务状态
ansible prometheus_cluster -i inventory/hosts.ini -m shell -a "systemctl status prometheus"

# 检查版本
curl http://192.168.31.80:9090/api/v1/status/buildinfo

# 检查目标
curl http://192.168.31.80:9090/api/v1/targets
```

### 检查 Node Exporter 状态
```bash
# 检查所有节点的 Node Exporter
ansible allNodes -i inventory/hosts.ini -m shell -a "systemctl status node_exporter"

# 测试单个节点
curl http://192.168.31.30:9100/metrics
```

## 集成 Grafana

Prometheus 已自动配置为 Grafana 的数据源。在 Grafana 中可以直接使用。

数据源配置:
- Name: Prometheus
- URL: http://192.168.31.80:9090
- Access: Server (default)

## 常见问题

### Prometheus 无法访问
检查防火墙和服务状态：
```bash
sudo systemctl status prometheus
sudo netstat -tlnp | grep 9090
```

### Node Exporter 指标缺失
确保 Node Exporter 在所有节点上运行：
```bash
ansible allNodes -i inventory/hosts.ini -m shell -a "systemctl status node_exporter"
```

### 代理配置问题
确保环境变量正确设置：
```bash
export http_proxy=http://192.168.31.132:20171
export https_proxy=http://192.168.31.132:20171
```

## 数据备份

Prometheus 数据存储在 `/var/lib/prometheus`，定期备份该目录：

```bash
# 备份数据
sudo tar -czf prometheus-backup-$(date +%Y%m%d).tar.gz /var/lib/prometheus

# 恢复数据
sudo systemctl stop prometheus
sudo tar -xzf prometheus-backup-YYYYMMDD.tar.gz -C /
sudo chown -R prometheus:prometheus /var/lib/prometheus
sudo systemctl start prometheus
```

## 性能优化

### 调整数据保留时间
编辑 `/etc/systemd/system/prometheus.service`，修改 `--storage.tsdb.retention.time` 参数。

### 增加内存限制
如果监控大量目标，可能需要增加内存：
```bash
# 编辑 systemd 服务文件
sudo systemctl edit prometheus

# 添加
[Service]
Environment="GOGC=40"
MemoryLimit=4G
```

## 卸载

```bash
# 停止服务
sudo systemctl stop prometheus node_exporter
sudo systemctl disable prometheus node_exporter

# 删除文件
sudo rm -rf /opt/prometheus /opt/node_exporter
sudo rm -f /etc/systemd/system/prometheus.service /etc/systemd/system/node_exporter.service
sudo rm -rf /var/lib/prometheus

# 删除用户
sudo userdel prometheus
sudo groupdel prometheus
```
