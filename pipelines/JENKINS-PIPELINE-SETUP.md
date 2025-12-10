# Jenkins Pipeline 创建和配置完整指南

此指南详细说明如何创建一个由 GitLab 存储配置并在 main 分支提交时自动触发的 Jenkins 流水线。

## 架构说明

本方案采用三台服务器分离架构：

- **Jenkins 服务器**: `192.168.31.70` - 负责流水线调度和任务触发
- **Ansible 控制节点**: `192.168.31.10` - 负责执行实际的部署任务
- **GitLab 服务器**: `192.168.31.50` - 存储代码和流水线配置

工作流程：
1. 开发者提交代码到 GitLab (`git@192.168.31.50:gaamingzhang/ansible.git`)
2. GitLab Webhook 触发 Jenkins (`192.168.31.70`)
3. Jenkins 通过 SSH 连接到 Ansible 控制节点 (`192.168.31.10`)
4. Ansible 控制节点执行部署任务到目标服务器

## 目录结构

```
ansible/                                 # GitLab 仓库根目录
├── pipelines/
│   ├── Jenkinsfile                      # Jenkins 流水线定义
│   ├── PostCommitDeploy.Jenkinsfile     # 提交触发的部署流水线
│   ├── jenkins-casc.yaml                # Jenkins 配置即代码
│   └── JENKINS-PIPELINE-SETUP.md        # 本文档
├── playbook/                            # Ansible playbooks
│   ├── kubernetes/                      # K8s 部署
│   ├── GitLab/                          # GitLab 部署
│   ├── Prometheus/                      # 监控部署
│   └── ...
├── inventory/                           # 主机清单
│   └── hosts.ini
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
| Generic Webhook Trigger | 通用Webhook触发器 | ✓ |
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
  workflow-aggregator generic-webhook-trigger ssh-agent credentials timestamper ansicolor
  
# 重启 Jenkins
sudo systemctl restart jenkins
```

### 2. 确认 Ansible 控制节点配置

在 Ansible 控制节点 (`192.168.31.10`) 上确认配置：

```bash
# 从 Jenkins 服务器 SSH 到 Ansible 控制节点
ssh node@192.168.31.10

# 确认 Ansible 已安装
ansible --version

# 确认项目路径存在
cd /home/node/ansible
ls -la

# 测试 Ansible 连接目标主机
ansible all -i inventory/hosts.ini -m ping
```

如果 Ansible 未安装：
```bash
ssh node@192.168.31.10
sudo apt update
sudo apt install -y ansible git
```

### 3. 配置 Jenkins 到 Ansible 控制节点的 SSH 访问

在 Jenkins 服务器 (`192.168.31.70`) 上：

```bash
# 切换到 jenkins 用户
sudo su - jenkins

# 创建 .ssh 目录（如果不存在）
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 生成 SSH 密钥（如果没有）
ssh-keygen -t rsa -b 4096 -C "jenkins@192.168.31.70" -f ~/.ssh/id_rsa -N ""

# 复制公钥到 Ansible 控制节点
ssh-copy-id node@192.168.31.10

# 测试连接
ssh node@192.168.31.10 "hostname && ansible --version"
```

将 Ansible 控制节点添加到 known_hosts：
```bash
sudo su - jenkins
ssh-keyscan 192.168.31.10 >> ~/.ssh/known_hosts
```

### 4. 配置 Jenkins 到 GitLab 的 SSH 信任

**关键步骤**：Jenkins 需要信任 GitLab 服务器的 SSH 主机密钥

在 Jenkins 服务器 (`192.168.31.70`) 上：

```bash
# 切换到 jenkins 用户（如果还没有）
sudo su - jenkins

# 确保 .ssh 目录存在
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 添加 GitLab 服务器的 SSH 主机密钥到 known_hosts
ssh-keyscan -t rsa,ecdsa,ed25519 192.168.31.50 >> ~/.ssh/known_hosts

# 设置正确的权限
chmod 644 ~/.ssh/known_hosts

# 验证密钥已添加
cat ~/.ssh/known_hosts | grep 192.168.31.50

# 测试 SSH 连接到 GitLab（会提示 Welcome to GitLab）
ssh -T git@192.168.31.50
```

如果测试连接失败，检查：
```bash
# 确保 known_hosts 文件权限正确
chmod 644 ~/.ssh/known_hosts

# 查看详细的 SSH 调试信息
ssh -vT git@192.168.31.50
```

> **重要**：如果不执行此步骤，Jenkins 扫描分支时会报错：
> ```
> No ED25519 host key is known for 192.168.31.50 and you have requested strict checking.
> Host key verification failed.
> ```

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

### 2.2 添加 Jenkins 到 Ansible 控制节点的 SSH 凭据

1. 在 Jenkins 服务器上获取 jenkins 用户的私钥:
```bash
# 在 Jenkins 服务器 (192.168.31.70) 上执行
sudo cat /var/lib/jenkins/.ssh/id_rsa
```

2. 在 Jenkins Web 界面添加凭据:
   - 访问: http://192.168.31.70:8080/manage/credentials/store/system/domain/_/
   - 点击 **Add Credentials**
   - 配置:
     - **Kind**: `SSH Username with private key`
     - **Scope**: `Global`
     - **ID**: `ansible-control-node-ssh`
     - **Description**: `SSH Key for Ansible Control Node (192.168.31.10)`
     - **Username**: `node`
     - **Private Key**: 选择 `Enter directly`
     - 点击 **Add** 按钮，粘贴私钥内容
   - 点击 **Create**

### 2.3 添加 GitLab SSH 私钥（用于拉取代码）

1. 在 Ansible 控制节点生成 SSH 密钥并添加到 GitLab:
```bash
# 在 Ansible 控制节点 (192.168.31.10) 上执行
ssh node@192.168.31.10

# 生成密钥（如果没有）
ssh-keygen -t rsa -b 4096 -C "ansible@192.168.31.10" -f ~/.ssh/id_rsa -N ""

# 查看公钥
cat ~/.ssh/id_rsa.pub
```

2. 将公钥添加到 GitLab:
   - 登录 GitLab: http://192.168.31.50
   - 进入项目: `gaamingzhang/ansible`
   - 点击 **Settings** → **Repository** → **Deploy Keys**
   - 点击 **Add new key**
   - **Title**: `Ansible Control Node`
   - **Key**: 粘贴公钥内容
   - ✓ **Grant write permissions** (如果需要)
   - 点击 **Add key**

3. 或者添加到用户的 SSH Keys（全局访问）:
   - 点击右上角头像 → **Preferences** → **SSH Keys**
   - 点击 **Add new key**
   - 粘贴公钥，点击 **Add key**

4. 测试 GitLab SSH 连接:
```bash
# 在 Ansible 控制节点上
ssh -T git@192.168.31.50
# 应该看到: Welcome to GitLab, @username!

# 测试克隆仓库
cd /tmp
git clone git@192.168.31.50:gaamingzhang/ansible.git test-clone
rm -rf test-clone
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
   - **Project Repository**: `git@192.168.31.50:gaamingzhang/ansible.git`
   - **Credentials**: 
     - 如果使用 SSH：需要添加 SSH 凭据（见下文）
     - 如果使用 HTTP：选择 `gitlab-api-token`
   - **Behaviors**:
     - 点击 **Add** → **Discover branches**
       - **Strategy**: `All branches`
     - 点击 **Add** → **Filter by name (with regular expression)**
       - **Regular expression**: `main` (只监控 main 分支)
     - 点击 **Add** → **Clean before checkout**
     - 点击 **Add** → **Clean after checkout**

> **配置 SSH 凭据（推荐）**：
> 1. 访问: http://192.168.31.70:8080/manage/credentials/store/system/domain/_/
> 2. 点击 **Add Credentials**
> 3. 配置:
>    - **Kind**: `SSH Username with private key`
>    - **Scope**: `Global`
>    - **ID**: `gitlab-ssh-key`
>    - **Description**: `SSH Key for GitLab (192.168.31.50)`
>    - **Username**: `git`
>    - **Private Key**: 选择 `Enter directly`
>    - 粘贴 Jenkins 用户的私钥: `sudo cat /var/lib/jenkins/.ssh/id_rsa`
> 4. 点击 **Create**
> 5. 返回 Job 配置，在 **Credentials** 中选择 `gitlab-ssh-key`
> 
> **重要**：确保已执行"步骤 0.4：配置 Jenkins 到 GitLab 的 SSH 信任"，否则会报 host key verification 错误

#### Build Configuration 部分:
- **Mode**: `by Jenkinsfile`
- **Script Path**: `pipelines/PostCommitDeploy.Jenkinsfile`

> **说明**: 使用 `PostCommitDeploy.Jenkinsfile` 专门处理 main 分支提交后的自动部署

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

有三种 Webhook 触发方式：

#### 方式 1: Generic Webhook Trigger（推荐）

最灵活的方式，适用于所有类型的 Job：

```
http://192.168.31.70:8080/generic-webhook-trigger/invoke?token=<YOUR_TOKEN>
```

#### 方式 2: Git Notify Commit

适用于 Git 仓库的提交通知：

```
http://192.168.31.70:8080/git/notifyCommit?url=http://192.168.31.50/gaamingzhang/ansible.git
```

#### 方式 3: Multibranch Webhook Trigger

专门用于 Multibranch Pipeline：

```
http://192.168.31.70:8080/multibranch-webhook-trigger/invoke?token=<YOUR_TOKEN>
```

**推荐使用方式1 (Generic Webhook Trigger)**，因为：
- 不需要特定格式的仓库URL
- GitLab能够轻松验证通过
- 支持自定义参数和过滤条件
- 更灵活的配置选项

### 5.2 配置 Generic Webhook Trigger

1. 进入 Jenkins Job 配置页面
2. 滚动到 **Build Triggers** 部分
3. 勾选 **Generic Webhook Trigger**
4. 配置 Token（重要）：
   - 点击 **Token** 输入框
   - 输入一个唯一的 token，例如：`ansible-infrastructure-deployment-token`
   - 这个 token 将用于 Webhook URL

5. （可选）添加过滤条件：
   - **Post content parameters**: 可以从 GitLab 的 Webhook payload 中提取变量
   - 例如提取分支名：
     - **Variable**: `branch`
     - **Expression**: `$.ref`
     - **JSONPath**: 勾选
   - **Optional filter**:
     - **Expression**: `^refs/heads/main$`
     - **Text**: `$branch`
     - 这样只有 main 分支的推送才会触发

6. 点击 **Save** 保存配置

### 5.3 配置 GitLab 网络出站请求（GitLab 18.6+）

**重要**: GitLab 18.6 默认限制向本地网络发送 Webhook 请求，需要先配置允许的出站请求。

#### 5.3.1 配置管理员网络出站设置

1. 以管理员身份登录 GitLab: http://192.168.31.50
2. 点击左上角菜单 → **Admin Area**（或访问 http://192.168.31.50/admin）
3. 左侧菜单选择 **Settings** → **Network**
4. 展开 **Outbound requests** 部分
5. 配置以下选项:
   - ✓ 勾选 **Allow requests to the local network from webhooks and integrations**
   - 在 **Local IP addresses and domain names that hooks and integrations can access** 中添加:
     ```
     192.168.31.70
     ```
   - 或者添加整个子网:
     ```
     192.168.31.0/24
     ```
6. 点击 **Save changes**

> **说明**: 
> - GitLab 18.x 为安全考虑，默认阻止 Webhook 向内网 IP 发送请求
> - 配置后才能向 Jenkins (192.168.31.70) 发送 Webhook
> - 建议只添加必要的 IP 地址，不要开放整个内网

#### 5.3.2 在 GitLab 项目配置 Webhook

1. 访问 GitLab 项目: http://192.168.31.50/gaamingzhang/ansible
2. 点击 **Settings** → **Webhooks**
3. 点击 **Add new webhook**
4. 配置:
   - **URL**: `http://192.168.31.70:8080/generic-webhook-trigger/invoke?token=ansible-infrastructure-deployment-token`
   - **Secret token**: (留空)
   - **Trigger**:
     - ✓ `Push events` - 分支: `main`
     - ✓ `Merge request events` (可选)
   - **SSL verification**: ✗ Enable SSL verification (因为使用 HTTP)
5. 点击 **Add webhook**

如果看到错误提示：
```
Url is blocked: Requests to the local network are not allowed
```
说明未完成步骤 5.3.1 的管理员配置，请先配置网络出站请求白名单。

> **关键优势**: 
> - **简单的URL格式**: 不包含仓库地址，只需要 token
> - **易于验证**: GitLab 可以轻松验证这种格式的 URL
> - **灵活配置**: 可以在 Jenkins 中自定义触发条件
> - **不依赖仓库URL**: 避免了 SSH 格式 URL 的验证问题

### 5.4 测试 Webhook（备选方案：Git Notify）

如果你更喜欢使用 Git Notify 方式，需要注意：

**重要**：GitLab Webhook URL 验证不接受包含特殊字符（如 `@`、`:`）的URL，因此必须使用 **HTTP 格式**的仓库地址。

配置:
- **URL**: `http://192.168.31.70:8080/git/notifyCommit?url=http://192.168.31.50/gaamingzhang/ansible.git`

> **说明**: 
> - **必须使用 HTTP 格式**: `http://192.168.31.50/gaamingzhang/ansible.git`
> - **不要使用 SSH 格式**: ~~`git@192.168.31.50:gaamingzhang/ansible.git`~~ (GitLab Webhook验证会拒绝)
> - Jenkins 的 `git/notifyCommit` 端点会智能匹配所有配置了该仓库的 Job（无论 Job 使用 SSH 还是 HTTP）

### 5.5 测试 Webhook

1. 在 Webhooks 列表中找到刚创建的 webhook
2. 点击 **Test** → **Push events**
3. 应该看到 HTTP 200 响应
4. 返回 Jenkins，应该看到新的构建开始或 **Scan Multibranch Pipeline Log** 中有新的扫描记录

如果测试失败，检查以下几点：
- Jenkins 服务是否运行: `ssh node@192.168.31.70 "sudo systemctl status jenkins"`
- 防火墙是否允许 GitLab 访问 Jenkins: `sudo ufw allow from 192.168.31.50 to any port 8080`
- URL 格式是否正确
- Token 是否正确（如果使用 Generic Webhook Trigger）
- 仓库 URL 是否使用 HTTP 格式（如果使用 Git Notify 方式）

## 步骤 6: 验证流水线

### 6.1 手动触发首次构建

1. 访问: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/
2. 点击 **Scan Multibranch Pipeline Now**
3. 等待扫描完成
4. 点击 **main** 分支
5. 应该看到构建历史

### 6.2 测试自动触发

在 Ansible 控制节点 (`192.168.31.10`) 或任何有权限的机器上：

```bash
# 克隆仓库（如果还没有）
git clone git@192.168.31.50:gaamingzhang/ansible.git
cd ansible

# 确保在 main 分支
git checkout main
git pull origin main

# 修改一个文件
echo "# Test Jenkins pipeline - $(date)" >> README.md

# 提交并推送到 main 分支
git add README.md
git commit -m "test: trigger Jenkins pipeline on main branch"
git push origin main
```

**预期行为**:
1. GitLab 接收到 push 到 main 分支
2. GitLab Webhook 自动触发 Jenkins
3. Jenkins 在 1 分钟内开始构建
4. 流水线检测变更的文件
5. 如果 playbook 目录有变更，自动执行相应的部署

### 6.3 查看构建日志

1. 访问: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/job/main/
2. 点击最新的构建号 (如 #1)
3. 点击 **Console Output** 查看详细日志

应该看到:
```
[Pipeline] stage (从 GitLab 检出代码)
Cloning repository git@192.168.31.50:gaamingzhang/ansible.git

[Pipeline] stage (连接到 Ansible 控制节点)
SSH to node@192.168.31.10

[Pipeline] stage (检测变更的 Playbook)
Detecting changed files in playbooks/...
Changed files:
  playbook/Prometheus/README.md

[Pipeline] stage (部署变更的组件)
Deploying Prometheus...
Running: ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml
```

## 步骤 7: 测试组件部署

### 7.1 修改 Prometheus playbook 触发部署

```bash
# 在任意有权限的机器上
cd ansible  # 你的本地仓库

# 修改 Prometheus 配置
echo "# Update monitoring config - $(date)" >> playbook/Prometheus/README.md

# 提交到 main 分支
git add playbook/Prometheus/README.md
git commit -m "feat: update Prometheus monitoring config"
git push origin main
```

### 7.2 观察 Jenkins 执行流程

1. **GitLab 触发**: Webhook 立即触发 Jenkins
2. **Jenkins 执行**:
   - 从 GitLab 克隆最新代码
   - SSH 连接到 Ansible 控制节点 (`192.168.31.10`)
   - 检测到 `playbook/Prometheus/` 目录有变更
   - 在 Ansible 控制节点上执行部署命令
3. **Ansible 部署**: 
   - Ansible 控制节点连接到 Prometheus 目标服务器
   - 执行部署任务

查看日志应该显示:
```
=== 检测变更的 Playbook ===
检测到变更: playbook/Prometheus/
部署标志: DEPLOY_PROMETHEUS=true

=== 连接到 Ansible 控制节点 ===
SSH: node@192.168.31.10

=== 在 Ansible 控制节点执行部署 ===
cd /home/node/ansible
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml

PLAY [部署 Prometheus] **********************
TASK [Gathering Facts] **********************
ok: [prometheus-server]
...
PLAY RECAP **********************************
prometheus-server : ok=15 changed=3
```

### 7.3 验证部署结果

```bash
# 在 Ansible 控制节点上验证
ssh node@192.168.31.10
cd /home/node/ansible

# 手动检查 Prometheus 状态
ansible prometheus_cluster -i inventory/hosts.ini -m shell -a "systemctl status prometheus" -b
```

## 工作流程图

```
┌─────────────────────────────────────────────────────────────────┐
│  开发者推送代码到 GitLab main 分支                                │
│  git push origin main                                           │
│  GitLab Server: 192.168.31.50                                  │
└────────────────────┬────────────────────────────────────────────┘
                     │ Webhook
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitLab Webhook 触发 Jenkins                                     │
│  POST http://192.168.31.70:8080/git/notifyCommit?url=http://... │
│  Jenkins Server: 192.168.31.70                                  │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Jenkins 从 GitLab 拉取最新代码                                  │
│  git clone git@192.168.31.50:gaamingzhang/ansible.git          │
│  读取: pipelines/PostCommitDeploy.Jenkinsfile                   │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Jenkins SSH 连接到 Ansible 控制节点                             │
│  ssh node@192.168.31.10                                         │
│  Ansible Control Node: 192.168.31.10                           │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  在 Ansible 控制节点检测变更                                      │
│  cd /home/node/ansible                                          │
│  git diff --name-only HEAD~1 HEAD                              │
│  检测 playbook/* 目录的变更                                       │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  设置部署标志                                                     │
│  if playbook/Kubernetes/* changed  → DEPLOY_K8S=true           │
│  if playbook/Prometheus/* changed  → DEPLOY_PROMETHEUS=true    │
│  if playbook/GitLab/* changed      → DEPLOY_GITLAB=true        │
│  ...                                                            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  在 Ansible 控制节点执行部署 (只部署变更的组件)                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ if DEPLOY_PROMETHEUS=true                                │  │
│  │   ansible-playbook -i inventory/hosts.ini \              │  │
│  │     playbook/Prometheus/deploy-prometheus.yml            │  │
│  └──────────────────────────────────────────────────────────┘  │
│  Ansible Control Node: 192.168.31.10                           │
└────────────────────┬────────────────────────────────────────────┘
                     │ SSH to target servers
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Ansible 连接目标服务器执行任务                                   │
│  - Prometheus Server                                            │
│  - Grafana Server                                               │
│  - Kubernetes Cluster                                           │
│  - Database Servers                                             │
│  - ...                                                          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  部署完成，Jenkins 显示结果                                       │
│  ✅ Success: 组件部署成功                                         │
│  ❌ Failure: 部署失败，查看日志                                   │
│  ⏭️  Skipped: 无变更，跳过部署                                   │
└─────────────────────────────────────────────────────────────────┘
```

## 数据流和连接关系

```
GitLab (192.168.31.50)
  ├─ 存储代码仓库: git@192.168.31.50:gaamingzhang/ansible.git
  ├─ 包含 Jenkinsfile: pipelines/PostCommitDeploy.Jenkinsfile
  └─ Webhook 触发 → Jenkins

Jenkins (192.168.31.70)
  ├─ 监听 GitLab Webhook
  ├─ 读取 Jenkinsfile 并执行流水线
  ├─ SSH 连接 → Ansible 控制节点 (使用凭据: ansible-control-node-ssh)
  └─ 显示部署结果和日志

Ansible 控制节点 (192.168.31.10)
  ├─ 接收 Jenkins SSH 连接
  ├─ 克隆/更新 GitLab 仓库
  ├─ 执行 ansible-playbook 命令
  └─ SSH 连接 → 目标服务器群

目标服务器群
  ├─ Kubernetes 集群
  ├─ 监控服务器 (Prometheus, Grafana)
  ├─ 数据库服务器 (MySQL, MongoDB, Redis)
  ├─ 应用服务器 (GitLab, Jenkins, Kafka)
  └─ 接收 Ansible 部署任务
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

**症状**: Test Connection 失败或 host key verification failed

**解决**:
```bash
# 在 Jenkins 服务器 (192.168.31.70) 上
# 切换到 jenkins 用户
sudo su - jenkins

# 添加 GitLab SSH 主机密钥
ssh-keyscan -t rsa,ecdsa,ed25519 192.168.31.50 >> ~/.ssh/known_hosts

# 测试 SSH 连接
ssh -T git@192.168.31.50
# 应该看到: Welcome to GitLab, @username!

# 如果使用 HTTP API，测试连接
curl http://192.168.31.50/api/v4/projects

# 检查防火墙
sudo ufw status
sudo ufw allow from 192.168.31.70 to any port 80
sudo ufw allow from 192.168.31.70 to any port 22
```

**常见错误**:
```
No ED25519 host key is known for 192.168.31.50 and you have requested strict checking.
Host key verification failed.
```
**原因**: Jenkins 的 known_hosts 文件中没有 GitLab 的主机密钥
**解决**: 执行上面的 `ssh-keyscan` 命令

### 问题 2: Jenkins 无法 SSH 到 Ansible 控制节点

**症状**: SSH 连接失败

**解决**:
```bash
# 在 Jenkins 服务器测试连接
sudo su - jenkins
ssh node@192.168.31.10 "hostname"

# 如果失败，重新配置
ssh-keyscan 192.168.31.10 >> ~/.ssh/known_hosts
ssh-copy-id node@192.168.31.10

# 检查 Ansible 控制节点的 SSH 服务
ssh node@192.168.31.10
sudo systemctl status ssh
```

### 问题 3: Ansible 控制节点无法拉取 GitLab 代码

**症状**: git clone 失败

**解决**:
```bash
# 在 Ansible 控制节点 (192.168.31.10) 上
ssh node@192.168.31.10

# 测试 SSH 连接到 GitLab
ssh -T git@192.168.31.50

# 添加 GitLab 到 known_hosts
ssh-keyscan 192.168.31.50 >> ~/.ssh/known_hosts

# 验证 SSH 密钥已添加到 GitLab
cat ~/.ssh/id_rsa.pub
# 复制公钥并在 GitLab 中检查是否已添加
```

### 问题 4: Webhook 未触发

**症状**: 推送代码后 Jenkins 没有构建

**解决**:
1. 检查 GitLab Webhook 日志:
   - Settings → Webhooks → Edit → Recent events
   - 查看响应码和错误信息

2. 验证 Jenkins URL 可从 GitLab 访问:
   ```bash
   # 在 GitLab 服务器 (192.168.31.50) 上测试
   ssh node@192.168.31.50
   curl -I "http://192.168.31.70:8080/git/notifyCommit?url=git@192.168.31.50:gaamingzhang/ansible.git"
   ```

3. 检查防火墙规则:
   ```bash
   # 在 Jenkins 服务器上
   sudo ufw allow from 192.168.31.50 to any port 8080
   ```

4. 确认 Webhook URL 格式正确:
   - **必须使用**: `http://192.168.31.70:8080/git/notifyCommit?url=http://192.168.31.50/gaamingzhang/ansible.git`
   - **不要使用**: ~~`http://192.168.31.70:8080/git/notifyCommit?url=git@192.168.31.50:gaamingzhang/ansible.git`~~
   - Webhook URL 中的仓库地址必须使用 HTTP 格式，GitLab 才能通过验证
   - Jenkins 会自动匹配所有配置了该仓库的 Job（无论 Job 内部使用 SSH 还是 HTTP）

5. 检查 Jenkins 日志:
   ```bash
   ssh node@192.168.31.70
   sudo journalctl -u jenkins -f
   sudo tail -f /var/log/jenkins/jenkins.log
   ```

6. 手动触发扫描验证 Job 配置正确:
   ```bash
   # 访问 Jenkins，点击 "Scan Multibranch Pipeline Now"
   # 或通过 API 触发
   curl -X POST http://192.168.31.70:8080/job/ansible-infrastructure-deployment/build
   ```

### 问题 5: Ansible 执行失败

**症状**: 流水线执行到 Ansible 阶段失败

**解决**:
```bash
# 在 Ansible 控制节点手动测试
ssh node@192.168.31.10
cd /home/node/ansible

# 测试 inventory 连接
ansible all -i inventory/hosts.ini -m ping

# 手动执行 playbook
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml -v

# 检查目标主机连接
ansible prometheus_cluster -i inventory/hosts.ini -m shell -a "hostname" -b
```

### 问题 6: 权限问题

**症状**: Permission denied

**解决**:
```bash
# 确保 Ansible 控制节点的项目目录权限正确
ssh node@192.168.31.10
sudo chown -R node:node /home/node/ansible
chmod 755 /home/node/ansible

# 确保 SSH 密钥权限正确
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

## 安全建议

1. ✅ 使用 SSH 密钥认证，而非密码
2. ✅ 定期轮换 GitLab API Token 和 SSH 密钥
3. ✅ 限制 Jenkins 用户权限和流水线访问权限
4. ✅ 使用 Role-Based Access Control (RBAC)
5. ✅ 审计构建日志，监控异常访问
6. ✅ 启用 Jenkins CSRF 保护
7. ✅ 定期备份 Jenkins 配置和 Ansible 控制节点数据
8. ✅ 使用防火墙限制服务器间的访问：
   - GitLab (192.168.31.50) → Jenkins (192.168.31.70): 允许 Webhook
   - Jenkins (192.168.31.70) → Ansible (192.168.31.10): 允许 SSH
   - Jenkins (192.168.31.70) → GitLab (192.168.31.50): 允许 Git 克隆
   - Ansible (192.168.31.10) → 目标服务器: 允许 SSH
9. ✅ 在 Ansible 控制节点上定期更新代码和依赖
10. ✅ 使用 Jenkins 凭据管理，不要在代码中硬编码密钥

## 监控和维护

### 定期检查服务状态

```bash
# 检查 Jenkins 服务
ssh node@192.168.31.70
sudo systemctl status jenkins
df -h /var/lib/jenkins

# 检查 Ansible 控制节点
ssh node@192.168.31.10
df -h /home/node
cd /home/node/ansible && git status

# 检查 GitLab 服务
ssh node@192.168.31.50
sudo gitlab-ctl status
```

### 查看流水线历史

```bash
# 访问 Blue Ocean 界面 (更友好的可视化)
http://192.168.31.70:8080/blue/organizations/jenkins/ansible-infrastructure-deployment/

# 或传统界面
http://192.168.31.70:8080/job/ansible-infrastructure-deployment/
```

### 清理旧构建

在 Jenkins Job 配置中:
- **Discard old builds**: 保留最近 10 次构建
- **Days to keep builds**: 30 天

### 手动清理

```bash
# 在 Jenkins 服务器清理旧工作区
ssh node@192.168.31.70
sudo find /var/lib/jenkins/workspace -mtime +30 -type f -delete

# 在 Ansible 控制节点清理旧日志
ssh node@192.168.31.10
find /home/node/ansible/logs -mtime +30 -type f -delete
```

### 备份关键数据

```bash
# 备份 Jenkins 配置
ssh node@192.168.31.70
sudo tar -czf /backup/jenkins-config-$(date +%Y%m%d).tar.gz /var/lib/jenkins/

# 备份 Ansible 控制节点
ssh node@192.168.31.10
tar -czf /backup/ansible-$(date +%Y%m%d).tar.gz /home/node/ansible/
```

## 总结

现在你有一个完整的三层分离架构 CI/CD 流程:

### 架构优势

✅ **代码管理**: GitLab (192.168.31.50) 统一存储所有配置
✅ **流水线调度**: Jenkins (192.168.31.70) 负责任务触发和监控
✅ **部署执行**: Ansible 控制节点 (192.168.31.10) 专注于执行部署
✅ **职责分离**: 各服务器各司其职，提高安全性和可维护性
✅ **自动触发**: 提交到 main 分支自动触发部署
✅ **智能检测**: 只部署变更的 playbook 组件
✅ **并行执行**: 多个组件可同时部署，提高效率
✅ **完整日志**: 从触发到部署的全链路日志追踪

### 工作流程回顾

1. **开发**: 在本地或任意机器修改 ansible 仓库
2. **提交**: `git push origin main` 推送到 GitLab
3. **触发**: GitLab Webhook 自动通知 Jenkins
4. **读取**: Jenkins 读取 `pipelines/PostCommitDeploy.Jenkinsfile`
5. **连接**: Jenkins SSH 到 Ansible 控制节点
6. **检测**: 在 Ansible 控制节点检测 playbook 变更
7. **部署**: Ansible 执行变更的组件部署
8. **完成**: Jenkins 显示部署结果

### 快速访问链接

- **GitLab**: http://192.168.31.50
  - 仓库: http://192.168.31.50/gaamingzhang/ansible
- **Jenkins**: http://192.168.31.70:8080
  - 流水线: http://192.168.31.70:8080/job/ansible-infrastructure-deployment/
  - Blue Ocean: http://192.168.31.70:8080/blue/
- **Ansible 控制节点**: `ssh node@192.168.31.10`
  - 项目路径: `/home/node/ansible`

### 下一步

1. 根据需要调整 `pipelines/PostCommitDeploy.Jenkinsfile`
2. 添加更多 playbook 组件的检测和部署逻辑
3. 配置邮件或 Slack 通知
4. 设置定期备份策略
5. 监控各服务器的资源使用情况

### 常用命令

```bash
# 测试流水线
cd /path/to/ansible
git commit --allow-empty -m "test: trigger pipeline"
git push origin main

# 查看 Jenkins 日志
ssh node@192.168.31.70 "sudo journalctl -u jenkins -f"

# 在 Ansible 控制节点手动部署
ssh node@192.168.31.10
cd /home/node/ansible
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml
```
