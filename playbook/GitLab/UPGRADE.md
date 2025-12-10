# GitLab 升级指南

## 升级路径

根据 GitLab 官方升级路径要求，从较低版本升级到 18.6.1 需要经过以下步骤：

1. **升级到 18.5.x** (中间版本)
2. **升级到 18.6.1** (目标版本)

## 执行升级

### 方法 1: 使用升级脚本 (推荐)

```bash
cd /home/node/ansible
ansible-playbook -i inventory/hosts.ini playbook/GitLab/upgrade-gitlab.yml
```

### 方法 2: 分步执行

#### 步骤 1: 升级到 18.5.3

```bash
ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml \
  -e "gitlab_version=18.5.3-ce.0"
```

#### 步骤 2: 升级到 18.6.1

```bash
ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml \
  -e "gitlab_version=18.6.1-ce.0"
```

## 升级前检查

### 1. 检查当前版本

```bash
ansible gitLab_cluster -i inventory/hosts.ini -m shell \
  -a "gitlab-rake gitlab:env:info | grep GitLab:" -b
```

### 2. 检查磁盘空间

```bash
ansible gitLab_cluster -i inventory/hosts.ini -m shell \
  -a "df -h /" -b
```

### 3. 创建备份

```bash
ansible gitLab_cluster -i inventory/hosts.ini -m shell \
  -a "gitlab-backup create SKIP=registry" -b
```

## 升级过程说明

自动升级脚本会执行以下操作：

1. **检查当前版本**
2. **创建备份** (可选)
3. **升级到 18.5.3**
   - 停止部分服务
   - 安装新版本
   - 重新配置
   - 重启服务
   - 健康检查
4. **升级到 18.6.1**
   - 重复上述步骤
5. **验证最终版本**

## 升级后验证

### 1. 检查版本

```bash
ansible gitLab_cluster -i inventory/hosts.ini -m shell \
  -a "gitlab-rake gitlab:env:info | grep GitLab:" -b
```

### 2. 检查服务状态

```bash
ansible gitLab_cluster -i inventory/hosts.ini -m shell \
  -a "gitlab-ctl status" -b
```

### 3. 检查健康状态

```bash
ansible gitLab_cluster -i inventory/hosts.ini -m shell \
  -a "gitlab-rake gitlab:check SANITIZE=true" -b
```

### 4. Web 访问测试

访问: http://192.168.31.50

## 故障恢复

如果升级失败，可以从备份恢复：

```bash
# 停止服务
gitlab-ctl stop unicorn
gitlab-ctl stop puma
gitlab-ctl stop sidekiq

# 恢复备份 (替换为实际的备份时间戳)
gitlab-backup restore BACKUP=<timestamp>

# 重启服务
gitlab-ctl restart

# 检查状态
gitlab-rake gitlab:check SANITIZE=true
```

## 注意事项

1. **备份重要**: 升级前务必备份数据
2. **磁盘空间**: 确保至少有 10GB 可用空间
3. **内存要求**: 建议至少 4GB RAM
4. **升级时间**: 每个步骤可能需要 10-20 分钟
5. **业务中断**: 升级期间服务会短暂中断
6. **版本跳跃**: 不要跳过中间版本

## 版本信息

- **起始版本**: 检测现有版本
- **中间版本**: 18.5.3-ce.0
- **目标版本**: 18.6.1-ce.0

## 参考文档

- [GitLab 官方升级文档](https://docs.gitlab.com/ee/update/)
- [GitLab 升级路径工具](https://gitlab-com.gitlab.io/support/toolbox/upgrade-path/)
