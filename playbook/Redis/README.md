# Redis 集群部署

使用 Ansible 自动化部署 Redis 集群（3 主节点模式，无密码认证）。

## 功能特性

- 自动安装 Redis 8.3.240 (stable)
- 自动配置 Redis 集群模式
- 支持 3 主节点集群（可扩展）
- 无密码认证配置
- 编译安装（支持 TLS）
- 系统优化配置
- 自动配置 systemd 服务

## 前置要求

1. Ubuntu 24.04 虚拟机（至少 3 台）
2. 每台至少 1GB RAM
3. 每台至少 10GB 磁盘空间
4. 虚拟机可访问互联网（或配置代理）
5. Ansible 已配置并可访问目标主机

## 虚拟机配置

在 `inventory/hosts.ini` 中配置:

```ini
[redis_cluster]
Redis000 ansible_host=192.168.31.90
Redis001 ansible_host=192.168.31.91
Redis002 ansible_host=192.168.31.92
```

## 部署步骤

```bash
cd /home/node/ansible
ansible-playbook -i inventory/hosts.ini playbook/Redis/deploy-redis-cluster.yml
```

## 配置说明

编辑 `playbook/Redis/roles/install-redis-cluster/defaults/main.yml`:

```yaml
# Redis 版本（使用 stable 分支获取最新稳定版）
redis_version: "8.0.1"

# 端口配置
redis_port: 6379
redis_cluster_port: 16379

# 密码配置（空字符串表示无密码）
redis_password: ""

# 集群配置
redis_cluster_enabled: true
redis_cluster_replicas: 0  # 0=无副本（3主节点），1=每个主节点1个副本（需6节点）

# 性能配置
redis_maxmemory: "256mb"
redis_maxmemory_policy: "allkeys-lru"
```

## 集群架构

### 当前配置（3 主节点，无副本）
- **Redis000** (192.168.31.90): Master - 哈希槽 0-5460 (5461 slots)
- **Redis001** (192.168.31.91): Master - 哈希槽 5461-10922 (5462 slots)
- **Redis002** (192.168.31.92): Master - 哈希槽 10923-16383 (5461 slots)

总计: 16384 个哈希槽

### 扩展到 6 节点（3主3从）

如需高可用配置，添加 3 个副本节点：

```ini
[redis_cluster]
Redis000 ansible_host=192.168.31.90
Redis001 ansible_host=192.168.31.91
Redis002 ansible_host=192.168.31.92
Redis003 ansible_host=192.168.31.93
Redis004 ansible_host=192.168.31.94
Redis005 ansible_host=192.168.31.95
```

修改 playbook 配置:
```yaml
redis_cluster_replicas: 1
```

## 连接 Redis 集群

### 使用 redis-cli（集群模式）
```bash
# 连接到集群（-c 启用集群模式）
/opt/redis/bin/redis-cli -c -h 192.168.31.90

# 查看集群信息
/opt/redis/bin/redis-cli -h 192.168.31.90 cluster info

# 查看集群节点
/opt/redis/bin/redis-cli -h 192.168.31.90 cluster nodes

# 查看哈希槽分配
/opt/redis/bin/redis-cli -h 192.168.31.90 cluster slots
```

### 基本操作
```bash
# 设置键值（自动路由到正确节点）
/opt/redis/bin/redis-cli -c -h 192.168.31.90 set mykey "Hello Redis Cluster"

# 获取值
/opt/redis/bin/redis-cli -c -h 192.168.31.90 get mykey

# 批量操作（同一哈希槽）
/opt/redis/bin/redis-cli -c -h 192.168.31.90 mset key1 value1 key2 value2

# 查看键所在槽
/opt/redis/bin/redis-cli -h 192.168.31.90 cluster keyslot mykey
```

### 使用 Python 连接
```python
from redis.cluster import RedisCluster

# 创建集群连接
rc = RedisCluster(
    startup_nodes=[
        {"host": "192.168.31.90", "port": 6379},
        {"host": "192.168.31.91", "port": 6379},
        {"host": "192.168.31.92", "port": 6379}
    ],
    decode_responses=True
)

# 使用集群
rc.set("mykey", "value")
print(rc.get("mykey"))
```

## 集群管理

### 查看集群状态
```bash
/opt/redis/bin/redis-cli -h 192.168.31.90 cluster info
```

输出说明：
- `cluster_state:ok` - 集群正常
- `cluster_slots_assigned:16384` - 所有槽位已分配
- `cluster_size:3` - 3 个主节点

### 添加节点

```bash
# 添加新主节点
/opt/redis/bin/redis-cli --cluster add-node 192.168.31.93:6379 192.168.31.90:6379

# 重新分配槽位
/opt/redis/bin/redis-cli --cluster reshard 192.168.31.90:6379
```

### 删除节点

```bash
# 删除节点
/opt/redis/bin/redis-cli --cluster del-node 192.168.31.90:6379 <node-id>
```

### 故障转移

如果某个主节点失败，手动触发故障转移：
```bash
/opt/redis/bin/redis-cli -h 192.168.31.91 cluster failover
```

## 监控

### 实时监控
```bash
# 监控命令执行
/opt/redis/bin/redis-cli -h 192.168.31.90 monitor

# 查看统计信息
/opt/redis/bin/redis-cli -h 192.168.31.90 info stats

# 查看内存使用
/opt/redis/bin/redis-cli -h 192.168.31.90 info memory

# 查看连接数
/opt/redis/bin/redis-cli -h 192.168.31.90 info clients
```

### 性能测试
```bash
# 基准测试
/opt/redis/bin/redis-benchmark -h 192.168.31.90 -p 6379 -c 50 -n 10000 -t set,get

# 集群模式测试
/opt/redis/bin/redis-benchmark -h 192.168.31.90 -p 6379 --cluster -c 50 -n 10000
```

## 备份和恢复

### RDB 备份（快照）
```bash
# 立即创建快照
/opt/redis/bin/redis-cli -h 192.168.31.90 bgsave

# 检查备份状态
/opt/redis/bin/redis-cli -h 192.168.31.90 lastsave

# 备份文件位置: /var/lib/redis/dump.rdb
sudo cp /var/lib/redis/dump.rdb /backup/redis-backup-$(date +%Y%m%d).rdb
```

### AOF 备份（增量）

启用 AOF：
```bash
# 编辑配置
sudo vim /etc/redis/redis.conf

# 添加
appendonly yes
appendfilename "appendonly.aof"

# 重启 Redis
sudo systemctl restart redis
```

### 恢复数据
```bash
# 停止 Redis
sudo systemctl stop redis

# 恢复 RDB 文件
sudo cp /backup/redis-backup-YYYYMMDD.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb

# 启动 Redis
sudo systemctl start redis
```

## 安全配置

### 启用密码认证

修改配置：
```yaml
redis_password: "your_strong_password"
```

重新部署：
```bash
ansible-playbook -i inventory/hosts.ini playbook/Redis/deploy-redis-cluster.yml
```

连接时使用密码：
```bash
/opt/redis/bin/redis-cli -c -h 192.168.31.90 -a your_strong_password
```

### 配置防火墙

```bash
# 允许 Redis 端口
sudo ufw allow 6379/tcp
sudo ufw allow 16379/tcp
```

## 性能优化

### 系统参数（已自动配置）
- `vm.overcommit_memory = 1` - 允许内存过量分配
- `net.core.somaxconn = 65535` - 增加连接队列
- 禁用透明大页 (Transparent Huge Pages)

### Redis 配置优化
```conf
# 持久化优化
save 900 1
save 300 10
save 60 10000

# 慢查询日志
slowlog-log-slower-than 10000
slowlog-max-len 128

# 最大连接数
maxclients 10000
```

## 常见问题

### 集群创建失败
检查节点是否可互相访问：
```bash
telnet 192.168.31.90 6379
telnet 192.168.31.90 16379
```

### 槽位分配不均
手动重新分配：
```bash
/opt/redis/bin/redis-cli --cluster rebalance 192.168.31.90:6379
```

### 内存不足
调整最大内存配置：
```yaml
redis_maxmemory: "512mb"
redis_maxmemory_policy: "allkeys-lru"
```

## 验证部署

```bash
# 检查所有 Redis 服务
ansible redis_cluster -i inventory/hosts.ini -m shell -a "systemctl status redis"

# 检查集群状态
ssh node@192.168.31.90 "/opt/redis/bin/redis-cli cluster info"

# 测试读写
ssh node@192.168.31.90 "/opt/redis/bin/redis-cli -c set test 'Hello Redis' && /opt/redis/bin/redis-cli -c get test"
```

## 卸载

```bash
# 停止服务
ansible redis_cluster -i inventory/hosts.ini -m shell -a "sudo systemctl stop redis" -b

# 删除文件
ansible redis_cluster -i inventory/hosts.ini -m shell -a "sudo rm -rf /opt/redis /etc/redis /var/lib/redis /var/log/redis" -b

# 删除用户
ansible redis_cluster -i inventory/hosts.ini -m shell -a "sudo userdel redis && sudo groupdel redis" -b
```
