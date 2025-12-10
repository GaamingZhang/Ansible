# ElasticSearch 部署

使用 Ansible 自动化部署 ElasticSearch 集群。

## 功能特性

- 自动安装最新版本的 ElasticSearch (8.x)
- 配置 ElasticSearch 单节点或集群模式
- 支持启用/禁用安全功能
- 配置系统参数优化
- 支持自定义配置

## 前置条件

- Ubuntu 操作系统
- Ansible 2.9+
- 目标主机需要有 sudo 权限
- 目标主机需要能够访问互联网

## 快速开始

### 1. 配置 Inventory

在 `inventory/hosts.ini` 中添加 ElasticSearch 节点:

```ini
[ElasticSearch_cluster]
ElasticSearch ansible_host=192.168.31.150
```

### 2. 配置变量（可选）

如需自定义配置,可以在 `group_vars/all.yml` 或创建 `group_vars/ElasticSearch_cluster.yml` 文件:

```yaml
# ElasticSearch 版本
elasticsearch_version: "8.x"

# 集群名称
elasticsearch_cluster_name: "elasticsearch-cluster"

# 内存配置
elasticsearch_heap_size: "1g"

# 网络配置
elasticsearch_network_host: "0.0.0.0"
elasticsearch_http_port: 9200
elasticsearch_transport_port: 9300

# 安全配置 (设置为 false 可无密码访问)
elasticsearch_enable_security: false

# 发现类型 (单节点: single-node)
elasticsearch_discovery_type: "single-node"
```

### 3. 执行部署

```bash
# 部署 ElasticSearch
ansible-playbook -i inventory/hosts.ini playbook/ElasticSearch/deploy-elasticsearch.yml
```

## 部署后操作

### 无密码访问模式 (默认)

```bash
# 检查集群健康状态
curl http://192.168.31.150:9200/_cluster/health?pretty

# 获取集群信息
curl http://192.168.31.150:9200

# 查看节点信息
curl http://192.168.31.150:9200/_cat/nodes?v
```

### 启用安全模式

如果 `elasticsearch_enable_security: true`，需要使用密码访问：

1. **获取 elastic 用户密码**

登录到 ElasticSearch 服务器:

```bash
sudo cat /root/elasticsearch_elastic_password.txt
```

2. **测试访问**

```bash
# 检查集群健康状态
curl -u elastic:<password> http://192.168.31.150:9200/_cluster/health?pretty

# 获取集群信息
curl -u elastic:<password> http://192.168.31.150:9200

# 查看节点信息
curl -u elastic:<password> http://192.168.31.150:9200/_cat/nodes?v
```

### 查看服务状态

```bash
# 查看服务状态
sudo systemctl status elasticsearch

# 查看日志
sudo journalctl -u elasticsearch -f

# 或查看日志文件
sudo tail -f /var/log/elasticsearch/elasticsearch-cluster.log
```

## 配置说明

### 主要配置文件

- `/etc/elasticsearch/elasticsearch.yml` - ElasticSearch 主配置文件
- `/etc/elasticsearch/jvm.options.d/heap.options` - JVM 堆内存配置
- `/var/lib/elasticsearch` - 数据目录
- `/var/log/elasticsearch` - 日志目录

### 默认配置

- **HTTP 端口**: 9200
- **传输端口**: 9300
- **集群名称**: elasticsearch-cluster
- **节点名称**: 主机名
- **堆内存**: 1GB
- **安全功能**: 已禁用（无密码访问）

## 安全说明

当前配置为**无密码访问模式**，适合开发测试环境。生产环境建议：

1. **启用安全功能**: 设置 `elasticsearch_enable_security: true`
2. **防火墙**: 配置防火墙规则限制访问
3. **SSL/TLS**: 启用 HTTPS 加密通信
4. **密码管理**: 使用强密码并定期更换

## 故障排查

### 服务无法启动

```bash
# 查看详细日志
sudo journalctl -u elasticsearch -n 100 --no-pager

# 检查配置文件语法
sudo /usr/share/elasticsearch/bin/elasticsearch --version
```

### 内存不足

调整 `elasticsearch_heap_size` 参数,建议设置为物理内存的一半,但不超过 31GB。

### 磁盘空间不足

ElasticSearch 默认在磁盘使用率达到 85% 时会将索引设为只读。确保有足够的磁盘空间。

## 卸载

```bash
# 停止服务
sudo systemctl stop elasticsearch

# 卸载软件包
sudo apt remove --purge elasticsearch

# 删除数据和配置
sudo rm -rf /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch
```

## 参考文档

- [ElasticSearch 官方文档](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [ElasticSearch 安装指南](https://www.elastic.co/guide/en/elasticsearch/reference/current/install-elasticsearch.html)
- [ElasticSearch 配置参考](https://www.elastic.co/guide/en/elasticsearch/reference/current/settings.html)

## 许可证

本项目使用 MIT 许可证。
