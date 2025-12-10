# MongoDB 部署指南

本文档介绍如何使用 Ansible 在 Ubuntu 虚拟机上部署 MongoDB 数据库（最新版本 8.0）。

## 目录结构

```
MongoDB/
├── deploy-mongodb.yml                  # 主部署 playbook
├── README.md                           # 本文档
└── roles/
    └── install-mongodb/
        ├── defaults/
        │   └── main.yml               # 默认变量配置
        ├── handlers/
        │   └── main.yml               # 服务处理程序
        ├── tasks/
        │   └── main.yml               # 安装任务
        └── templates/
            └── mongod.conf.j2         # MongoDB 配置模板
```

## 前置要求

- Ubuntu 虚拟机（已在 inventory 中定义为 MongoDB_cluster 组）
- SSH 访问权限和 sudo 权限
- 互联网连接（用于下载 MongoDB 包）

## 配置说明

### 1. Inventory 配置

虚拟机已在 `inventory/hosts.ini` 中定义：

```ini
[MongoDB_cluster]
MongoDB ansible_host=192.168.31.140
```

### 2. 变量配置

在 `roles/install-mongodb/defaults/main.yml` 中配置：

```yaml
# MongoDB 版本（留空则安装最新版本 8.0）
mongodb_version: ""

# 网络配置
mongodb_port: 27017
mongodb_bind_ip: 0.0.0.0

# 数据和日志目录
mongodb_data_dir: /var/lib/mongodb
mongodb_log_dir: /var/log/mongodb

# 认证配置
mongodb_auth_enabled: true
mongodb_root_username: admin
mongodb_root_password: "ChangeMe123!"  # 建议修改

# 应用数据库用户（可选）
mongodb_users: []
#  - name: appuser
#    password: "apppass123"
#    database: appdb
#    roles: "readWrite"
```

### 3. 自定义配置（可选）

在 `group_vars/all.yml` 或创建 `group_vars/MongoDB_cluster.yml` 覆盖默认变量：

```yaml
# 示例：自定义 root 密码
mongodb_root_password: "YourSecurePassword123!"

# 示例：创建应用用户
mongodb_users:
  - name: myapp
    password: "myapp123"
    database: myappdb
    roles: "readWrite"
```

## 部署步骤

### 1. 测试连接

```bash
ansible MongoDB_cluster -m ping
```

### 2. 部署 MongoDB

```bash
# 从项目根目录执行
cd /home/node/ansible
ansible-playbook playbook/MongoDB/deploy-mongodb.yml

# 或者使用完整路径
ansible-playbook -i inventory/hosts.ini playbook/MongoDB/deploy-mongodb.yml
```

### 3. 指定版本部署（可选）

如果需要安装特定版本，修改配置后执行：

```bash
ansible-playbook playbook/MongoDB/deploy-mongodb.yml -e "mongodb_version=8.0.4"
```

## 部署内容

部署过程将完成以下操作：

1. **系统准备**
   - 更新 APT 缓存
   - 安装依赖包（gnupg, curl, ca-certificates）

2. **MongoDB 仓库配置**
   - 添加 MongoDB GPG 密钥
   - 配置 MongoDB 8.0 APT 仓库

3. **MongoDB 安装**
   - 安装最新版本的 MongoDB（8.0.x）
   - 安装 mongosh（MongoDB Shell）
   - 安装相关工具

4. **目录和权限配置**
   - 创建数据目录 `/var/lib/mongodb`
   - 创建日志目录 `/var/log/mongodb`
   - 配置系统限制（文件描述符、进程数）

5. **服务配置**
   - 部署 MongoDB 配置文件 `/etc/mongod.conf`
   - 启动并启用 MongoDB 服务
   - 配置开机自启动

6. **安全配置**
   - 创建管理员用户（root 权限）
   - 启用身份认证
   - 可选：创建应用数据库用户

## 验证部署

### 1. 检查服务状态

```bash
ansible MongoDB_cluster -m shell -a "systemctl status mongod" -b
```

### 2. 检查版本

```bash
ansible MongoDB_cluster -m shell -a "mongod --version" -b
```

### 3. 测试连接

在目标服务器上：

```bash
# 无认证测试（仅在认证未启用时）
mongosh --host 192.168.31.140 --port 27017

# 使用管理员账户连接
mongosh -u admin -p --authenticationDatabase admin

# 连接并检查数据库
mongosh -u admin -p 'ChangeMe123!' --authenticationDatabase admin --eval "db.adminCommand('listDatabases')"
```

## 连接信息

- **主机**: 192.168.31.140
- **端口**: 27017
- **管理员用户**: admin
- **连接字符串**: `mongodb://admin:密码@192.168.31.140:27017/admin`

## 常用命令

### 服务管理

```bash
# 启动服务
sudo systemctl start mongod

# 停止服务
sudo systemctl stop mongod

# 重启服务
sudo systemctl restart mongod

# 查看状态
sudo systemctl status mongod

# 查看日志
sudo tail -f /var/log/mongodb/mongod.log
```

### MongoDB Shell 操作

```bash
# 连接到 MongoDB
mongosh -u admin -p --authenticationDatabase admin

# 查看数据库列表
show dbs

# 创建数据库
use mydb

# 创建用户
db.createUser({
  user: "myuser",
  pwd: "mypassword",
  roles: [ { role: "readWrite", db: "mydb" } ]
})

# 查看用户
db.getUsers()
```

## 安全建议

1. **修改默认密码**
   - 立即修改 `mongodb_root_password` 为强密码
   - 使用 Ansible Vault 加密敏感变量

2. **网络安全**
   - 如果不需要远程访问，设置 `mongodb_bind_ip: 127.0.0.1`
   - 配置防火墙规则限制访问

3. **启用 TLS/SSL**（生产环境推荐）
   ```yaml
   # 在配置文件中添加
   net:
     tls:
       mode: requireTLS
       certificateKeyFile: /path/to/cert.pem
   ```

4. **备份策略**
   - 定期备份数据库
   - 使用 `mongodump` 和 `mongorestore` 命令

## 故障排查

### 服务无法启动

```bash
# 查看详细日志
sudo journalctl -u mongod -n 50

# 查看 MongoDB 日志
sudo tail -n 100 /var/log/mongodb/mongod.log

# 检查配置文件语法
sudo mongod --config /etc/mongod.conf --check
```

### 连接被拒绝

1. 检查服务是否运行：`sudo systemctl status mongod`
2. 检查端口监听：`sudo netstat -tlnp | grep 27017`
3. 检查防火墙：`sudo ufw status`
4. 检查绑定地址：`grep bindIp /etc/mongod.conf`

### 认证失败

1. 确认用户名和密码正确
2. 确认使用正确的认证数据库：`--authenticationDatabase admin`
3. 检查认证是否启用：`grep authorization /etc/mongod.conf`

## 卸载 MongoDB

如需卸载：

```bash
# 停止服务
sudo systemctl stop mongod
sudo systemctl disable mongod

# 卸载软件包
sudo apt-get purge mongodb-org*

# 删除数据和日志（可选）
sudo rm -rf /var/log/mongodb
sudo rm -rf /var/lib/mongodb

# 删除配置文件
sudo rm /etc/mongod.conf
```

## 参考资料

- [MongoDB 官方文档](https://docs.mongodb.com/)
- [MongoDB 安装指南 - Ubuntu](https://docs.mongodb.com/manual/tutorial/install-mongodb-on-ubuntu/)
- [MongoDB 安全检查清单](https://docs.mongodb.com/manual/administration/security-checklist/)

## 版本信息

- MongoDB 版本: 8.0.x (最新)
- 支持系统: Ubuntu 20.04, 22.04, 24.04
- Ansible 版本要求: >= 2.9
