# GitLab CI/CD 自动部署配置指南

## 配置步骤

### 1. 在 GitLab 项目中配置 SSH 私钥

1. 进入项目: http://192.168.31.50/gaamingzhang/ansible
2. 点击 **Settings** → **CI/CD** → **Variables**
3. 添加变量:
   - **Key**: `SSH_PRIVATE_KEY`
   - **Value**: 粘贴 Ansible 控制节点的 SSH 私钥内容
   - **Type**: File
   - **Protected**: ✓ (勾选)
   - **Masked**: ✗ (不勾选，因为私钥太长)

#### 获取 SSH 私钥:
```bash
# 在 Ansible 控制节点上执行
cat ~/.ssh/id_rsa
```

### 2. 配置 GitLab Runner

#### 方法 A: 使用 Ansible 控制节点作为 Runner (推荐)

在控制节点 (192.168.31.132) 上安装 GitLab Runner:

```bash
# 安装 GitLab Runner
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# 注册 Runner
sudo gitlab-runner register \
  --non-interactive \
  --url "http://192.168.31.50/" \
  --registration-token "你的注册token" \
  --executor "shell" \
  --description "ansible-control-node" \
  --tag-list "ansible,deploy" \
  --run-untagged="true" \
  --locked="false"

# 配置 Runner 使用当前用户
sudo gitlab-runner install --user=node --working-directory=/home/node
sudo systemctl restart gitlab-runner
```

获取注册 token:
- 进入 GitLab 项目 → **Settings** → **CI/CD** → **Runners** → **Specific runners**
- 复制显示的 registration token

#### 方法 B: 使用 Docker Runner

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 启动 GitLab Runner 容器
docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest

# 注册 Runner
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://192.168.31.50/" \
  --registration-token "你的注册token" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "docker-runner" \
  --tag-list "docker,ansible" \
  --run-untagged="true" \
  --locked="false" \
  --docker-network-mode="host"
```

### 3. 验证配置

#### 检查 Runner 状态:
```bash
sudo gitlab-runner list
sudo gitlab-runner verify
```

在 GitLab 界面检查:
- 进入项目 → **Settings** → **CI/CD** → **Runners**
- 确认看到绿色的 Runner (表示已连接)

### 4. 测试 CI/CD

提交并推送一个变更到 main 分支:

```bash
# 修改任意 playbook 文件
echo "# test" >> playbook/Prometheus/README.md

# 提交并推送
git add .
git commit -m "test: trigger CI/CD pipeline"
git push origin main
```

查看流水线:
- 进入项目 → **CI/CD** → **Pipelines**
- 点击最新的流水线查看执行状态

## CI/CD 工作流程

### 流程说明

```
┌─────────────────┐
│ Merge to main   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ detect_changes  │  检测哪些 playbook 被修改
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ deploy_*        │  并行部署被修改的服务
└─────────────────┘
```

### 触发条件

- **自动触发**: commit 合并到 `main` 分支时
- **手动触发**: 在 GitLab 界面点击 "Run Pipeline"

### 检测逻辑

Pipeline 会自动检测以下目录的变更:
- `playbook/kubernetes/` → 部署 Kubernetes 集群
- `playbook/GitLab/` → 部署 GitLab
- `playbook/Jenkins/` → 部署 Jenkins
- `playbook/Prometheus/` → 部署 Prometheus + Node Exporter
- `playbook/Grafana/` → 部署 Grafana
- `playbook/Redis/` → 部署 Redis 集群
- `playbook/MySQL/` → 部署 MySQL
- `playbook/MongoDB/` → 部署 MongoDB
- `playbook/ElasticSearch/` → 部署 ElasticSearch
- `playbook/Kafka/` → 部署 Kafka

### 并行执行

所有检测到变更的服务会并行部署，提高效率。

## 高级配置

### 1. 添加环境变量

在 GitLab **Settings** → **CI/CD** → **Variables** 中添加:

| Key | Value | Description |
|-----|-------|-------------|
| `SSH_PRIVATE_KEY` | 私钥内容 | Ansible SSH 认证 |
| `ANSIBLE_VAULT_PASSWORD` | vault密码 | 如果使用 Ansible Vault |
| `HTTP_PROXY` | http://192.168.31.132:20171 | HTTP 代理 |
| `HTTPS_PROXY` | http://192.168.31.132:20171 | HTTPS 代理 |

### 2. 添加通知

在 `.gitlab-ci.yml` 末尾添加:

```yaml
notify_success:
  stage: .post
  only:
    - main
  script:
    - echo "Deployment successful!"
    # 可以添加邮件、Slack、钉钉通知等

notify_failure:
  stage: .post
  when: on_failure
  only:
    - main
  script:
    - echo "Deployment failed!"
    # 可以添加告警通知
```

### 3. 手动确认

如果希望在部署前需要手动确认:

```yaml
deploy_kubernetes:
  stage: deploy
  when: manual  # 添加这行
  # ... 其他配置
```

### 4. 仅在特定分支运行

修改 `only` 配置:

```yaml
only:
  - main
  - /^release-.*$/  # 匹配 release-* 分支
```

## 故障排查

### Runner 无法连接到目标主机

检查 SSH 配置:
```bash
# 在 Runner 上测试
ssh -i ~/.ssh/id_rsa node@192.168.31.30
```

### Ansible 找不到 inventory

确保 Runner 的工作目录正确:
```bash
sudo gitlab-runner list
# 检查 working directory
```

### 权限问题

确保 Runner 用户有权限:
```bash
sudo chown -R node:node /home/node/ansible
sudo chmod 600 ~/.ssh/id_rsa
```

### Pipeline 一直 Pending

检查 Runner 状态:
- GitLab 界面: **Settings** → **CI/CD** → **Runners**
- 确保至少有一个绿色的 Runner

### 查看详细日志

在 GitLab Pipeline 界面点击具体的 job，查看完整输出。

## 安全建议

1. **使用 Protected Variables**: CI/CD 变量应标记为 Protected
2. **限制 Runner 权限**: Runner 应使用专用用户，避免 root 权限
3. **SSH Key 轮换**: 定期更换 SSH 密钥
4. **审计日志**: 定期检查 GitLab 的审计日志
5. **网络隔离**: Runner 应在受信任的网络环境中运行

## 监控和告警

### 集成 Prometheus 监控

GitLab 本身也提供 Prometheus metrics:
- http://192.168.31.50/-/metrics

可以添加到 Prometheus 监控中:

```yaml
- job_name: 'gitlab'
  static_configs:
    - targets: ['192.168.31.50:80']
```

### 部署失败告警

可以在 Grafana 中创建告警规则，监控 CI/CD 失败率。

## 参考资料

- [GitLab CI/CD 文档](https://docs.gitlab.com/ee/ci/)
- [GitLab Runner 文档](https://docs.gitlab.com/runner/)
- [Ansible 最佳实践](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
