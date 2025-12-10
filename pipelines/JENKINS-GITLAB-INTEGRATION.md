# Jenkins 与 GitLab 集成配置指南

## 前置条件

1. Jenkins 已安装以下插件:
   - GitLab Plugin
   - Git Plugin
   - Pipeline Plugin
   - Credentials Plugin

## 配置步骤

### 1. 在 GitLab 中创建访问令牌

1. 访问: http://192.168.31.50/-/profile/personal_access_tokens
2. 点击 **Add new token**
3. 配置:
   - **Token name**: `jenkins-access`
   - **Expiration date**: 选择一个较长的日期
   - **Scopes**: 勾选以下权限:
     - ✓ api
     - ✓ read_api
     - ✓ read_repository
     - ✓ write_repository
4. 点击 **Create personal access token**
5. **立即复制令牌** (只显示一次)

### 2. 在 Jenkins 中添加 GitLab 凭据

1. 访问: http://192.168.31.70:8080/manage/credentials/
2. 点击 **(global)** → **Add Credentials**
3. 配置:
   - **Kind**: GitLab API token
   - **Scope**: Global
   - **API token**: 粘贴刚才创建的 GitLab 令牌
   - **ID**: `gitlab-api-token`
   - **Description**: GitLab API Token
4. 点击 **Create**

### 3. 配置 Jenkins GitLab 连接

1. 访问: http://192.168.31.70:8080/manage/configure
2. 找到 **GitLab** 部分
3. 点击 **Add GitLab Server** → **GitLab Server**
4. 配置:
   - **Name**: `Local GitLab`
   - **GitLab host URL**: `http://192.168.31.50`
   - **Credentials**: 选择 `gitlab-api-token`
5. 点击 **Test Connection** 验证
6. 点击 **Save**

### 4. 创建 Multibranch Pipeline Job

#### 方式 A: 通过 UI 创建

1. 访问: http://192.168.31.70:8080/
2. 点击 **New Item**
3. 输入名称: `ansible-deployment`
4. 选择 **Multibranch Pipeline**
5. 点击 **OK**
6. 配置:

   **Branch Sources**:
   - 点击 **Add source** → **GitLab Project**
   - **Server**: 选择 `Local GitLab`
   - **Checkout Credentials**: 选择 SSH 或 HTTP 凭据
   - **Owner**: `gaamingzhang`
   - **Projects**: 选择 `ansible`
   
   **Build Configuration**:
   - **Mode**: by Jenkinsfile
   - **Script Path**: `Jenkinsfile`
   
   **Scan Multibranch Pipeline Triggers**:
   - ✓ Periodically if not otherwise run
   - **Interval**: 1 minute (或其他间隔)
   
   **GitLab Project Trigger**:
   - ✓ Build on Push Events
   - ✓ Build on Merge Request Events

7. 点击 **Save**

#### 方式 B: 使用 Job DSL (推荐,可自动化)

创建 Job DSL 脚本:

```groovy
multibranchPipelineJob('ansible-deployment') {
    displayName('Ansible Infrastructure Deployment')
    description('自动部署基础设施变更')
    
    branchSources {
        git {
            id('ansible-repo')
            remote('http://192.168.31.50/gaamingzhang/ansible.git')
            credentialsId('gitlab-credentials')
            
            traits {
                gitLabBranchDiscovery {
                    strategyId(3) // Discover all branches
                }
                gitLabTagDiscovery()
            }
        }
    }
    
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
    
    orphanedItemStrategy {
        discardOldItems {
            numToKeep(10)
        }
    }
    
    triggers {
        periodic(1) // 每分钟扫描一次
    }
}
```

### 5. 配置 GitLab Webhook (推送时自动触发)

1. 在 Jenkins Job 页面,找到 **GitLab webhook URL**
   - 例如: `http://192.168.31.70:8080/project/ansible-deployment`

2. 访问 GitLab 项目: http://192.168.31.50/gaamingzhang/ansible/-/settings/integrations

3. 配置 Webhook:
   - **URL**: 粘贴 Jenkins webhook URL
   - **Secret token**: (可选)
   - **Trigger**: 勾选:
     - ✓ Push events (main 分支)
     - ✓ Merge request events
   - ✓ Enable SSL verification (如果使用 HTTPS)

4. 点击 **Add webhook**

5. 点击 **Test** → **Push events** 测试连接

### 6. 配置 SSH 凭据 (用于 Ansible)

1. 访问: http://192.168.31.70:8080/manage/credentials/
2. 点击 **(global)** → **Add Credentials**
3. 配置:
   - **Kind**: SSH Username with private key
   - **Scope**: Global
   - **ID**: `ansible-ssh-key`
   - **Description**: Ansible SSH Key
   - **Username**: `node`
   - **Private Key**: 选择 **Enter directly**
   - 粘贴 `/home/node/.ssh/id_rsa` 的内容
4. 点击 **Create**

### 7. 更新 Jenkinsfile 使用凭据

```groovy
pipeline {
    agent any
    
    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Setup SSH') {
            steps {
                sshagent(['ansible-ssh-key']) {
                    sh '''
                        ssh-keyscan 192.168.31.30 >> ~/.ssh/known_hosts
                        ansible-playbook -i inventory/hosts.ini playbook/...
                    '''
                }
            }
        }
    }
}
```

## 工作流程

```
GitLab Push/MR → Webhook → Jenkins → 拉取代码 → 执行 Jenkinsfile → 运行 Ansible
```

### 完整流程:

1. **开发者推送代码到 GitLab**
   ```bash
   git push origin main
   ```

2. **GitLab 触发 Webhook**
   - 通知 Jenkins 有新的提交

3. **Jenkins 自动拉取代码**
   - 从 GitLab 克隆/更新仓库

4. **Jenkins 读取 Jenkinsfile**
   - 检测哪些 playbook 被修改

5. **执行 Ansible 部署**
   - 只部署发生变更的服务

6. **查看结果**
   - Jenkins: http://192.168.31.70:8080/job/ansible-deployment/
   - 查看构建日志和状态

## 测试集成

### 测试 1: 修改配置触发构建

```bash
cd /home/node/ansible
echo "# test jenkins integration" >> README.md
git add README.md
git commit -m "test: trigger Jenkins build"
git push origin main
```

### 测试 2: 验证 Jenkins 自动构建

1. 访问: http://192.168.31.70:8080/job/ansible-deployment/
2. 应该看到新的构建开始
3. 点击构建号查看日志

### 测试 3: 验证 Ansible 执行

在 Jenkins 构建日志中应该看到:
```
检测哪些 playbook 被修改...
变更的文件:
README.md
```

## 故障排查

### 问题 1: Jenkins 无法连接 GitLab

- 检查防火墙: `telnet 192.168.31.50 80`
- 验证 API Token 权限
- 查看 Jenkins 日志: `sudo journalctl -u jenkins -f`

### 问题 2: Webhook 无法触发

- 检查 GitLab Webhook 日志: Settings → Integrations → Edit → Recent events
- 验证 Jenkins URL 可访问
- 检查 Jenkins 安全设置

### 问题 3: Ansible 执行失败

- 验证 SSH 密钥配置
- 检查 Jenkins 用户权限
- 查看 Ansible 执行日志

## 高级配置

### 多分支策略

```groovy
pipeline {
    agent any
    
    stages {
        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                // 只在 main 分支部署生产环境
            }
        }
        
        stage('Deploy to Staging') {
            when {
                branch 'dev'
            }
            steps {
                // dev 分支部署测试环境
            }
        }
    }
}
```

### 参数化构建

```groovy
pipeline {
    agent any
    
    parameters {
        choice(
            name: 'DEPLOY_TARGET',
            choices: ['all', 'kubernetes', 'monitoring', 'databases'],
            description: '选择部署目标'
        )
    }
    
    stages {
        stage('Deploy') {
            steps {
                script {
                    if (params.DEPLOY_TARGET == 'all' || params.DEPLOY_TARGET == 'kubernetes') {
                        sh 'ansible-playbook ...'
                    }
                }
            }
        }
    }
}
```

## 安全建议

1. ✅ 使用 HTTPS (如果可能)
2. ✅ 限制 API Token 权限
3. ✅ 定期轮换凭据
4. ✅ 使用 Secret Text 存储敏感信息
5. ✅ 审计 Jenkins 和 GitLab 日志
