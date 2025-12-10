# Jenkins Pipeline 创建和配置完整指南

此指南详细说明如何创建一个由 GitLab 存储配置并在 main 分支提交时自动触发的 Jenkins 流水线。

## 目录结构

```
ansible/
├── pipelines/
│   ├── Jenkinsfile                      # Jenkins 流水线定义
│   ├── jenkins-casc.yaml                # Jenkins 配置即代码
│   └── JENKINS-PIPELINE-SETUP.md        # 本文档
├── playbook/                            # Ansible playbooks
├── inventory/                           # 主机清单
└── ansible.cfg                          # Ansible 配置
```

## 前置条件

### 1. 安装必需的 Jenkins 插件

访问: http://192.168.31.70:8080/manage/pluginManager/

安装以下插件:

| 插件名称 | 说明 | 必需 |
|---------|------|-----|
| GitLab Plugin | GitLab 集成 | ✓ |
| Git Plugin | Git 源码管理 | ✓ |
| Pipeline | 流水线支持 | ✓ |
| Pipeline: Multibranch | 多分支流水线 | ✓ |
| SSH Agent Plugin | SSH 密钥管理 | ✓ |
| Credentials Plugin | 凭据管理 | ✓ |
| Timestamper | 时间戳 | 推荐 |
| AnsiColor | 彩色输出 | 推荐 |

安装命令:
```bash
# SSH 到 Jenkins 服务器
ssh node@192.168.31.70

# 使用 jenkins-cli 安装插件
java -jar /var/cache/jenkins/war/WEB-INF/jenkins-cli.jar -s http://localhost:8080/ \
  install-plugin gitlab-plugin git pipeline-model-definition \
  workflow-aggregator ssh-agent credentials timestamper ansicolor
  
# 重启 Jenkins
sudo systemctl restart jenkins
```

### 2. 确认 Ansible 已安装

在 Jenkins 服务器上:
```bash
ssh node@192.168.31.70
ansible --version
```

如果未安装:
```bash
sudo apt update
sudo apt install -y ansible
```

## 步骤 1: 在 GitLab 创建 Personal Access Token

### 1.1 生成访问令牌

1. 登录 GitLab: http://192.168.31.50
2. 点击右上角头像 → **Preferences**
3. 左侧菜单选择 **Access Tokens**
4. 点击 **Add new token**
5. 配置:
   - **Token name**: `jenkins-integration`
   - **Expiration date**: 2026-12-31 (或更长)
   - **Select scopes**:
     - ✓ `api` - 完整 API 访问
     - ✓ `read_api` - 读取 API
     - ✓ `read_repository` - 读取仓库
     - ✓ `write_repository` - 写入仓库
6. 点击 **Create personal access token**
7. **立即复制令牌** (只显示一次!): `glpat-xxxxxxxxxxxxxxxxxxxx`

### 1.2 保存令牌

```bash
# 临时保存到文件
echo "glpat-your-token-here" > /tmp/gitlab-token.txt
chmod 600 /tmp/gitlab-token.txt
```

## 步骤 2: 在 Jenkins 配置凭据

### 2.1 添加 GitLab API Token

1. 访问: http://192.168.31.70:8080/manage/credentials/store/system/domain/_/
2. 点击 **Add Credentials**
3. 配置:
   - **Kind**: `GitLab API token`
   - **Scope**: `Global (Jenkins, nodes, items, all child items, etc)`
   - **API token**: 粘贴刚才复制的 GitLab token
   - **ID**: `gitlab-api-token`
   - **Description**: `GitLab API Token for ansible project`
4. 点击 **Create**

### 2.2 添加 Ansible SSH 私钥

1. 获取 Ansible 控制节点的 SSH 私钥:
```bash
cat ~/.ssh/id_rsa
```

2. 在 Jenkins 添加凭据:
   - 访问: http://192.168.31.70:8080/manage/credentials/store/system/domain/_/
   - 点击 **Add Credentials**
   - 配置:
     - **Kind**: `SSH Username with private key`
     - **Scope**: `Global`
     - **ID**: `ansible-ssh-key`
     - **Description**: `Ansible SSH Key for Infrastructure`
     - **Username**: `node`
     - **Private Key**: 选择 `Enter directly`
     - 点击 **Add** 按钮,粘贴私钥内容
   - 点击 **Create**

### 2.3 验证凭据

```bash
# 在 Jenkins 服务器上测试 SSH
ssh -i ~/.ssh/id_rsa node@192.168.31.30 "echo SSH connection successful"
```

## 步骤 3: 配置 GitLab 连接

### 3.1 在 Jenkins 配置 GitLab 服务器

1. 访问: http://192.168.31.70:8080/manage/configure
2. 滚动到 **GitLab** 部分
3. 点击 **Add GitLab Server**
4. 配置:
   - **Name**: `Local GitLab`
   - **GitLab host URL**: `http://192.168.31.50`
   - **Credentials**: 选择 `gitlab-api-token`
5. 点击 **Test Connection** - 应该显示 "Success"
6. 点击 **Save**

## 步骤 4: 创建 Multibranch Pipeline Job

### 4.1 创建新 Job

1. 访问 Jenkins 首页: http://192.168.31.70:8080/
2. 点击 **New Item**
3. 输入名称: `ansible-infrastructure-deployment`
4. 选择 **Multibranch Pipeline**
5. 点击 **OK**

### 4.2 配置 Branch Sources

在配置页面:

#### General 部分:
- **Display Name**: `Ansible Infrastructure Deployment`
- **Description**: `自动检测变更并部署基础设施组件`

#### Branch Sources 部分:

1. 点击 **Add source** → **Git**
2. 配置:
   - **Project Repository**: `http://192.168.31.50/gaamingzhang/ansible.git`
   - **Credentials**: 选择 `gitlab-api-token`
   - **Behaviors**:
     - 点击 **Add** → **Discover branches**
       - **Strategy**: `All branches`
     - 点击 **Add** → **Filter by name (with regular expression)**
       - **Regular expression**: `main|dev` (只监控 main 和 dev 分支)

#### Build Configuration 部分:
- **Mode**: `by Jenkinsfile`
- **Script Path**: `pipelines/Jenkinsfile`

#### Scan Multibranch Pipeline Triggers 部分:
- ✓ **Periodically if not otherwise run**
- **Interval**: `1 minute`

#### Orphaned Item Strategy 部分:
- **Days to keep old items**: `7`
- **Max # of old items to keep**: `10`

### 4.3 保存配置

点击 **Save** 按钮

## 步骤 5: 配置 GitLab Webhook

### 5.1 获取 Webhook URL

1. 在 Jenkins Job 页面,点击左侧的 **Branch Indexing Log**
2. 或者直接访问: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/

Webhook URL 格式:
```
http://192.168.31.70:8080/project/ansible-infrastructure-deployment
```

### 5.2 在 GitLab 配置 Webhook

1. 访问 GitLab 项目: http://192.168.31.50/gaamingzhang/ansible
2. 点击 **Settings** → **Webhooks**
3. 点击 **Add new webhook**
4. 配置:
   - **URL**: `http://192.168.31.70:8080/project/ansible-infrastructure-deployment`
   - **Secret token**: (留空或生成一个)
   - **Trigger**:
     - ✓ `Push events` - 分支: `main`
     - ✓ `Merge request events`
   - **SSL verification**: ✗ (因为使用 HTTP)
5. 点击 **Add webhook**

### 5.3 测试 Webhook

1. 在 Webhooks 列表中找到刚创建的 webhook
2. 点击 **Test** → **Push events**
3. 应该看到 HTTP 200 响应
4. 返回 Jenkins,应该看到新的构建开始

## 步骤 6: 验证流水线

### 6.1 手动触发首次构建

1. 访问: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/
2. 点击 **Scan Multibranch Pipeline Now**
3. 等待扫描完成
4. 点击 **main** 分支
5. 应该看到构建历史

### 6.2 测试自动触发

```bash
cd /home/node/ansible

# 修改一个文件
echo "# Test Jenkins pipeline" >> README.md

# 提交并推送
git add README.md
git commit -m "test: trigger Jenkins pipeline"
git push origin main
```

### 6.3 查看构建日志

1. 访问: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/job/main/
2. 点击最新的构建号 (如 #1)
3. 点击 **Console Output** 查看详细日志

应该看到:
```
=== 从 GitLab 检出代码 ===
=== 检测哪些 playbook 被修改 ===
变更的文件:
README.md
=== 部署计划 ===
Kubernetes:    false
GitLab:        false
...
```

## 步骤 7: 测试组件部署

### 7.1 修改 Prometheus playbook 触发部署

```bash
cd /home/node/ansible

# 修改 Prometheus 配置
echo "# test deployment" >> playbook/Prometheus/README.md

# 提交
git add playbook/Prometheus/README.md
git commit -m "feat: update Prometheus config"
git push origin main
```

### 7.2 观察 Jenkins 执行

1. GitLab Webhook 触发 Jenkins
2. Jenkins 检测到 `playbook/Prometheus/` 变更
3. 只执行 Prometheus 部署阶段
4. 其他组件被跳过

查看日志应该显示:
```
=== 部署计划 ===
Prometheus:    true
(其他都是 false)

=== 部署 Prometheus 监控系统 ===
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml
```

## 工作流程图

```
┌─────────────────────────────────────────────────────────────────┐
│  开发者推送代码到 GitLab main 分支                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitLab Webhook 触发 Jenkins                                     │
│  URL: http://192.168.31.70:8080/project/ansible-infra...        │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Jenkins 从 GitLab 拉取最新代码                                  │
│  git clone http://192.168.31.50/gaamingzhang/ansible.git        │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  读取 pipelines/Jenkinsfile                                      │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  检测变更: git diff --name-only HEAD~1 HEAD                      │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  设置部署标志                                                     │
│  DEPLOY_KUBERNETES=false                                        │
│  DEPLOY_PROMETHEUS=true  (如果 playbook/Prometheus/ 变更)       │
│  DEPLOY_GRAFANA=false                                           │
│  ...                                                            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  并行执行部署 (只运行标志为 true 的)                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Kubernetes   │  │ Prometheus   │  │ Grafana      │          │
│  │ (跳过)       │  │ (执行)       │  │ (跳过)       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  使用 SSH 密钥执行 Ansible                                        │
│  sshagent(['ansible-ssh-key']) {                                │
│    ansible-playbook -i inventory/hosts.ini ...                  │
│  }                                                              │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  部署完成,发送通知 (可选)                                         │
│  ✅ Success 或 ❌ Failure                                        │
└─────────────────────────────────────────────────────────────────┘
```

## 高级配置

### 参数化构建

如果需要手动选择部署目标:

修改 `pipelines/Jenkinsfile`,在 `pipeline {` 后添加:

```groovy
parameters {
    choice(
        name: 'DEPLOY_TARGET',
        choices: ['auto', 'all', 'kubernetes', 'monitoring', 'databases', 'applications'],
        description: '选择部署目标 (auto=根据变更自动检测)'
    )
    booleanParam(
        name: 'DRY_RUN',
        defaultValue: false,
        description: '仅检查,不实际部署'
    )
}
```

### 通知集成

在 `post` 部分添加通知:

```groovy
post {
    success {
        // 发送成功通知到 Slack/Email
        mail to: 'devops@example.com',
             subject: "✅ Deploy Success: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
             body: "Deployment completed successfully"
    }
    failure {
        // 发送失败告警
        mail to: 'devops@example.com',
             subject: "❌ Deploy Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
             body: "Deployment failed. Check logs: ${env.BUILD_URL}"
    }
}
```

## 故障排查

### 问题 1: Jenkins 无法连接 GitLab

**症状**: Test Connection 失败

**解决**:
```bash
# 在 Jenkins 服务器测试连接
ssh node@192.168.31.70
curl http://192.168.31.50/api/v4/projects

# 检查防火墙
sudo ufw status
sudo ufw allow from 192.168.31.70 to any port 80
```

### 问题 2: SSH 认证失败

**症状**: Ansible 无法连接目标主机

**解决**:
```bash
# 验证 SSH 密钥
ssh node@192.168.31.70
ssh -i ~/.ssh/id_rsa node@192.168.31.30 "echo test"

# 添加主机到 known_hosts
ssh-keyscan 192.168.31.30 >> ~/.ssh/known_hosts
```

### 问题 3: Webhook 未触发

**症状**: 推送代码后 Jenkins 没有构建

**解决**:
1. 检查 GitLab Webhook 日志:
   - Settings → Webhooks → Edit → Recent events
2. 验证 Jenkins URL 可访问:
   ```bash
   curl http://192.168.31.70:8080/project/ansible-infrastructure-deployment
   ```
3. 检查 Jenkins 日志:
   ```bash
   sudo journalctl -u jenkins -f
   ```

### 问题 4: 并行执行失败

**症状**: 某些 stage 执行失败

**解决**:
- 检查资源限制 (CPU/内存)
- 查看 Ansible 日志
- 在 Jenkinsfile 中添加 `failFast: false` 允许其他 stage 继续

## 安全建议

1. ✅ 使用 HTTPS 连接 GitLab (如果可能)
2. ✅ 定期轮换 API Token
3. ✅ 限制 Jenkins 用户权限
4. ✅ 使用 Role-Based Access Control
5. ✅ 审计构建日志
6. ✅ 启用 Jenkins CSRF 保护
7. ✅ 定期备份 Jenkins 配置

## 监控和维护

### 查看流水线历史

```bash
# 访问 Blue Ocean 界面 (更友好)
http://192.168.31.70:8080/blue/organizations/jenkins/ansible-infrastructure-deployment/
```

### 清理旧构建

在 Jenkins Job 配置中:
- **Discard old builds**: 保留最近 10 次构建
- **Days to keep builds**: 30 天

### 定期检查

```bash
# 每周检查 Jenkins 磁盘空间
ssh node@192.168.31.70
df -h /var/lib/jenkins

# 清理旧工作区
sudo find /var/lib/jenkins/workspace -mtime +30 -delete
```

## 总结

现在你有一个完整的 CI/CD 流程:

✅ Jenkinsfile 存储在 GitLab (`pipelines/Jenkinsfile`)
✅ 推送到 main 分支自动触发部署
✅ 智能检测变更,只部署修改的组件
✅ 并行执行,提高效率
✅ 完整的日志和通知

访问 Jenkins 查看流水线: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/
