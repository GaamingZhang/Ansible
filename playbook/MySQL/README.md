# MySQL 数据库部署

使用 Ansible 自动化部署 MySQL 8.0（无密码认证）。

## 功能特性

- 自动安装 MySQL 8.0.44 (Ubuntu 官方仓库最新版本)
- 无密码认证配置
- 远程访问已启用
- 性能优化配置
- UTF-8 字符集支持
- 二进制日志启用（用于备份和复制）
- 慢查询日志启用

## 前置要求

1. Ubuntu 24.04 虚拟机
2. 至少 2GB RAM (推荐 4GB)
3. 至少 20GB 磁盘空间
4. 虚拟机可访问互联网（或配置代理）
5. Ansible 已配置并可访问目标主机

## 虚拟机配置

在 `inventory/hosts.ini` 中配置:

```ini
[mysql_cluster]
MySQL ansible_host=192.168.31.110
```

## 部署步骤

```bash
cd /home/node/ansible
ansible-playbook -i inventory/hosts.ini playbook/MySQL/deploy-mysql.yml
```

## 配置说明

编辑 `playbook/MySQL/roles/install-mysql/defaults/main.yml`:

```yaml
# MySQL 配置
mysql_root_password: ""  # 空字符串表示无密码
mysql_bind_address: "0.0.0.0"  # 允许远程连接
mysql_port: 3306
mysql_max_connections: 500
mysql_innodb_buffer_pool_size: "1G"

# 数据目录
mysql_datadir: "/var/lib/mysql"
mysql_log_error: "/var/log/mysql/error.log"

# 可选：创建数据库
mysql_databases:
  - name: myapp_db
    encoding: utf8mb4
    collation: utf8mb4_unicode_ci

# 可选：创建用户
mysql_users:
  - name: myapp_user
    password: "mypassword"
    priv: "myapp_db.*:ALL"
    host: "%"
```

## 连接 MySQL

### 本地连接（无密码）
```bash
# 在 MySQL 服务器上
mysql -u root

# 查看数据库
mysql -u root -e "SHOW DATABASES;"

# 查看版本
mysql -u root -e "SELECT VERSION();"
```

### 远程连接（无密码）
```bash
# 从任何主机连接
mysql -h 192.168.31.110 -u root

# 执行 SQL
mysql -h 192.168.31.110 -u root -e "SHOW DATABASES;"
```

### 使用 Python 连接
```python
import pymysql

# 创建连接
conn = pymysql.connect(
    host='192.168.31.110',
    port=3306,
    user='root',
    password='',  # 无密码
    database='mysql',
    charset='utf8mb4'
)

# 执行查询
cursor = conn.cursor()
cursor.execute("SELECT VERSION()")
version = cursor.fetchone()
print(f"MySQL Version: {version[0]}")

cursor.close()
conn.close()
```

## 数据库管理

### 创建数据库
```sql
-- 创建数据库
CREATE DATABASE myapp_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 查看数据库
SHOW DATABASES;

-- 使用数据库
USE myapp_db;
```

### 创建表
```sql
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 用户管理
```sql
-- 创建用户（有密码）
CREATE USER 'myuser'@'%' IDENTIFIED BY 'password123';

-- 授权
GRANT ALL PRIVILEGES ON myapp_db.* TO 'myuser'@'%';
FLUSH PRIVILEGES;

-- 查看用户
SELECT user, host FROM mysql.user;

-- 删除用户
DROP USER 'myuser'@'%';
```

### 启用密码认证

如需启用密码，修改配置并重新部署：

```yaml
mysql_root_password: "your_strong_password"
```

手动设置密码：
```bash
mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'your_password';
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'your_password';
FLUSH PRIVILEGES;
EOF
```

## 备份和恢复

### 使用 mysqldump 备份

```bash
# 备份单个数据库
mysqldump -u root myapp_db > myapp_db_backup.sql

# 备份所有数据库
mysqldump -u root --all-databases > all_databases_backup.sql

# 备份并压缩
mysqldump -u root --all-databases | gzip > backup_$(date +%Y%m%d).sql.gz

# 排除某些表
mysqldump -u root myapp_db --ignore-table=myapp_db.logs > myapp_db_backup.sql
```

### 恢复数据

```bash
# 恢复数据库
mysql -u root myapp_db < myapp_db_backup.sql

# 恢复压缩备份
gunzip < backup_20251210.sql.gz | mysql -u root

# 恢复所有数据库
mysql -u root < all_databases_backup.sql
```

### 自动备份脚本

创建 `/usr/local/bin/mysql-backup.sh`:
```bash
#!/bin/bash
BACKUP_DIR="/backup/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/mysql_backup_$DATE.sql.gz"

mkdir -p $BACKUP_DIR

mysqldump -u root --all-databases | gzip > $BACKUP_FILE

# 保留最近 7 天的备份
find $BACKUP_DIR -name "mysql_backup_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
```

设置 cron 定时任务：
```bash
# 每天凌晨 2 点备份
0 2 * * * /usr/local/bin/mysql-backup.sh
```

## 性能优化

### InnoDB 配置

已优化配置 (`/etc/mysql/mysql.conf.d/custom.cnf`):
```ini
[mysqld]
# InnoDB 缓冲池大小（推荐为物理内存的 70-80%）
innodb_buffer_pool_size = 1G

# 日志刷新策略（2=每秒刷新一次，性能较好）
innodb_flush_log_at_trx_commit = 2

# I/O 方法
innodb_flush_method = O_DIRECT

# 连接数
max_connections = 500
```

### 慢查询日志

已启用慢查询日志，查看慢查询：
```bash
# 查看慢查询日志
sudo tail -f /var/log/mysql/slow.log

# 分析慢查询
sudo mysqldumpslow -s t -t 10 /var/log/mysql/slow.log
```

### 查询优化

```sql
-- 查看当前运行的查询
SHOW FULL PROCESSLIST;

-- 分析查询
EXPLAIN SELECT * FROM users WHERE username = 'john';

-- 查看表索引
SHOW INDEX FROM users;

-- 创建索引
CREATE INDEX idx_username ON users(username);
```

## 监控

### 查看 MySQL 状态
```sql
-- 连接数
SHOW STATUS LIKE 'Threads_connected';

-- 查询统计
SHOW STATUS LIKE 'Questions';
SHOW STATUS LIKE 'Com_select';

-- InnoDB 状态
SHOW ENGINE INNODB STATUS;

-- 表大小
SELECT 
    table_schema AS 'Database',
    table_name AS 'Table',
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Size (MB)'
FROM information_schema.TABLES
ORDER BY (data_length + index_length) DESC;
```

### 系统资源监控
```bash
# 查看 MySQL 进程
ps aux | grep mysql

# 内存使用
top -p $(pgrep mysqld)

# 磁盘使用
du -sh /var/lib/mysql
```

## 复制配置（主从）

### 配置主服务器

编辑 `/etc/mysql/mysql.conf.d/custom.cnf`:
```ini
[mysqld]
server-id = 1
log_bin = /var/log/mysql/mysql-bin.log
binlog_do_db = myapp_db
```

创建复制用户：
```sql
CREATE USER 'replicator'@'%' IDENTIFIED BY 'replica_password';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;

-- 获取二进制日志位置
SHOW MASTER STATUS;
```

### 配置从服务器

编辑 `/etc/mysql/mysql.conf.d/custom.cnf`:
```ini
[mysqld]
server-id = 2
relay_log = /var/log/mysql/mysql-relay-bin.log
```

配置复制：
```sql
CHANGE MASTER TO
    MASTER_HOST='192.168.31.110',
    MASTER_USER='replicator',
    MASTER_PASSWORD='replica_password',
    MASTER_LOG_FILE='mysql-bin.000001',
    MASTER_LOG_POS=12345;

START SLAVE;

-- 检查状态
SHOW SLAVE STATUS\G
```

## 安全加固

### 启用密码认证
```sql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'strong_password';
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'strong_password';
FLUSH PRIVILEGES;
```

### 限制远程访问

编辑配置文件，限制绑定地址：
```ini
bind-address = 127.0.0.1  # 仅本地访问
```

或使用防火墙：
```bash
# 仅允许特定 IP 访问 MySQL
sudo ufw allow from 192.168.31.0/24 to any port 3306
```

### 删除匿名用户和测试数据库
```sql
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
```

## 验证部署

```bash
# 检查服务状态
ansible mysql_cluster -i inventory/hosts.ini -m shell -a "systemctl status mysql"

# 检查版本
ssh node@192.168.31.110 "mysql -u root -e 'SELECT VERSION();'"

# 测试连接
ssh node@192.168.31.110 "mysql -u root -e 'SHOW DATABASES;'"

# 检查远程访问
mysql -h 192.168.31.110 -u root -e "SELECT 'Connection successful' AS result;"
```

## 常见问题

### 无法远程连接
1. 检查防火墙：`sudo ufw status`
2. 检查绑定地址：`grep bind-address /etc/mysql/mysql.conf.d/*.cnf`
3. 检查用户权限：`SELECT user, host FROM mysql.user WHERE user='root';`

### MySQL 启动失败
查看错误日志：
```bash
sudo tail -100 /var/log/mysql/error.log
```

### 性能问题
1. 增加 InnoDB 缓冲池大小
2. 优化查询（添加索引）
3. 检查慢查询日志
4. 考虑读写分离

## 卸载

```bash
# 停止服务
sudo systemctl stop mysql

# 卸载软件包
sudo apt remove --purge mysql-server mysql-client mysql-common

# 删除数据
sudo rm -rf /var/lib/mysql /etc/mysql

# 删除用户
sudo userdel mysql
sudo groupdel mysql
```

## 升级 MySQL

```bash
# 备份数据
mysqldump -u root --all-databases > backup_before_upgrade.sql

# 停止服务
sudo systemctl stop mysql

# 更新软件包
sudo apt update
sudo apt upgrade mysql-server

# 启动服务
sudo systemctl start mysql

# 升级系统表
sudo mysql_upgrade -u root
```
