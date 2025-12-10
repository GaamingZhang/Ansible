// Jenkins Pipeline 配置
// 文件: DeployAll.Jenkinsfile
// 说明: 连接到 Ansible 控制节点并执行所有 playbook 部署

pipeline {
    agent any
    
    parameters {
        booleanParam(
            name: 'DEPLOY_KUBERNETES',
            defaultValue: true,
            description: '部署 Kubernetes 集群'
        )
        booleanParam(
            name: 'DEPLOY_PROMETHEUS',
            defaultValue: true,
            description: '部署 Prometheus 监控'
        )
        booleanParam(
            name: 'DEPLOY_GRAFANA',
            defaultValue: true,
            description: '部署 Grafana 可视化'
        )
        booleanParam(
            name: 'DEPLOY_GITLAB',
            defaultValue: true,
            description: '部署 GitLab'
        )
        booleanParam(
            name: 'DEPLOY_JENKINS',
            defaultValue: true,
            description: '部署 Jenkins'
        )
        booleanParam(
            name: 'DEPLOY_REDIS',
            defaultValue: true,
            description: '部署 Redis 集群'
        )
        booleanParam(
            name: 'DEPLOY_MYSQL',
            defaultValue: true,
            description: '部署 MySQL 数据库'
        )
        booleanParam(
            name: 'DEPLOY_MONGODB',
            defaultValue: true,
            description: '部署 MongoDB 数据库'
        )
        booleanParam(
            name: 'DEPLOY_ELASTICSEARCH',
            defaultValue: true,
            description: '部署 ElasticSearch'
        )
        booleanParam(
            name: 'DEPLOY_KAFKA',
            defaultValue: true,
            description: '部署 Kafka 消息队列'
        )
        choice(
            name: 'DEPLOYMENT_MODE',
            choices: ['parallel','sequential'],
            description: '部署模式: parallel=并行部署, sequential=顺序部署'
        )
        booleanParam(
            name: 'REQUIRE_APPROVAL',
            defaultValue: true,
            description: '是否在每个组件部署前需要手动批准'
        )
    }
    
    environment {
        ANSIBLE_CONTROL_NODE = '192.168.31.10'
        ANSIBLE_USER = 'node'
        ANSIBLE_PROJECT_DIR = '/home/node/ansible'
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_FORCE_COLOR = 'True'
    }
    
    stages {
        stage('准备阶段') {
            steps {
                echo "=========================================="
                echo "全栈基础设施自动化部署"
                echo "=========================================="
                echo "Ansible 控制节点: ${ANSIBLE_CONTROL_NODE}"
                echo "部署用户: ${ANSIBLE_USER}"
                echo "项目目录: ${ANSIBLE_PROJECT_DIR}"
                echo "部署模式: ${params.DEPLOYMENT_MODE}"
                echo "=========================================="
            }
        }
        
        stage('连接测试') {
            steps {
                echo "测试连接到 Ansible 控制节点..."
                withCredentials([sshUserPrivateKey(credentialsId: 'ansible-control-node-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            echo "✓ 成功连接到 Ansible 控制节点"
                            echo "主机名: \$(hostname)"
                            echo "当前用户: \$(whoami)"
                            echo ""
                            echo "Ansible 版本:"
                            ansible --version
                            echo ""
                            echo "项目路径: ${ANSIBLE_PROJECT_DIR}"
                            ls -la ${ANSIBLE_PROJECT_DIR}
                        '
                    """
                }
            }
        }
        
        stage('更新代码') {
            steps {
                echo "从 GitLab 拉取最新代码..."
                withCredentials([sshUserPrivateKey(credentialsId: 'ansible-control-node-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            echo "当前分支:"
                            git branch
                            echo ""
                            echo "拉取最新代码..."
                            git pull origin main
                            echo ""
                            echo "最新提交:"
                            git log -1 --oneline
                        '
                    """
                }
            }
        }
        
        stage('部署基础设施') {
            steps {
                script {
                    if (params.DEPLOYMENT_MODE == 'parallel') {
                        echo "使用并行部署模式..."
                        echo "✓ 每个组件独立批准和部署，互不影响"
                        
                        def parallelStages = [:]
                        
                        if (params.DEPLOY_KUBERNETES) {
                            parallelStages["Kubernetes"] = {
                                stage('Kubernetes') {
                                    try {
                                        requestApproval('Kubernetes')
                                        deployPlaybook('Kubernetes', 'playbook/kubernetes/deploy-k8s-cluster.yml')
                                    } catch (Exception e) {
                                        echo "❌ Kubernetes 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_PROMETHEUS) {
                            parallelStages["Prometheus"] = {
                                stage('Prometheus') {
                                    try {
                                        requestApproval('Prometheus')
                                        deployPlaybook('Prometheus', 'playbook/Prometheus/deploy-prometheus.yml')
                                        deployPlaybook('Node Exporter', 'playbook/Prometheus/deploy-node-exporter-all.yml')
                                        deployPlaybook('Prometheus Config', 'playbook/Prometheus/update-prometheus-config.yml')
                                    } catch (Exception e) {
                                        echo "❌ Prometheus 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_GRAFANA) {
                            parallelStages["Grafana"] = {
                                stage('Grafana') {
                                    try {
                                        requestApproval('Grafana')
                                        deployPlaybook('Grafana', 'playbook/Grafana/deploy-grafana.yml')
                                    } catch (Exception e) {
                                        echo "❌ Grafana 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_GITLAB) {
                            parallelStages["GitLab"] = {
                                stage('GitLab') {
                                    try {
                                        requestApproval('GitLab')
                                        deployPlaybook('GitLab', 'playbook/GitLab/deploy-gitlab.yml')
                                    } catch (Exception e) {
                                        echo "❌ GitLab 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_JENKINS) {
                            parallelStages["Jenkins"] = {
                                stage('Jenkins') {
                                    try {
                                        requestApproval('Jenkins')
                                        deployPlaybook('Jenkins', 'playbook/Jenkins/deploy-jenkins.yml')
                                    } catch (Exception e) {
                                        echo "❌ Jenkins 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_REDIS) {
                            parallelStages["Redis"] = {
                                stage('Redis') {
                                    try {
                                        requestApproval('Redis')
                                        deployPlaybook('Redis', 'playbook/Redis/deploy-redis-cluster.yml')
                                    } catch (Exception e) {
                                        echo "❌ Redis 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_MYSQL) {
                            parallelStages["MySQL"] = {
                                stage('MySQL') {
                                    try {
                                        requestApproval('MySQL')
                                        deployPlaybook('MySQL', 'playbook/MySQL/deploy-mysql.yml')
                                    } catch (Exception e) {
                                        echo "❌ MySQL 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_MONGODB) {
                            parallelStages["MongoDB"] = {
                                stage('MongoDB') {
                                    try {
                                        requestApproval('MongoDB')
                                        deployPlaybook('MongoDB', 'playbook/MongoDB/deploy-mongodb.yml')
                                    } catch (Exception e) {
                                        echo "❌ MongoDB 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_ELASTICSEARCH) {
                            parallelStages["ElasticSearch"] = {
                                stage('ElasticSearch') {
                                    try {
                                        requestApproval('ElasticSearch')
                                        deployPlaybook('ElasticSearch', 'playbook/ElasticSearch/deploy-elasticsearch.yml')
                                    } catch (Exception e) {
                                        echo "❌ ElasticSearch 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        if (params.DEPLOY_KAFKA) {
                            parallelStages["Kafka"] = {
                                stage('Kafka') {
                                    try {
                                        requestApproval('Kafka')
                                        deployPlaybook('Kafka', 'playbook/Kafka/deploy-kafka.yml')
                                    } catch (Exception e) {
                                        echo "❌ Kafka 部署失败或被中止: ${e.message}"
                                        currentBuild.result = 'UNSTABLE'
                                    }
                                }
                            }
                        }
                        
                        // 并行执行所有组件，失败不影响其他组件
                        parallel parallelStages
                        
                    } else {
                        echo "使用顺序部署模式..."
                        echo "使用顺序部署模式..."
                        echo "⚠️  组件将依次部署，失败或拒绝会中止后续部署"
                        
                        if (params.DEPLOY_KUBERNETES) {
                            stage('部署 Kubernetes') {
                                requestApproval('Kubernetes 集群')
                                deployPlaybook('Kubernetes 集群', 'playbook/kubernetes/deploy-k8s-cluster.yml')
                            }
                        }
                        
                        if (params.DEPLOY_PROMETHEUS) {
                            stage('部署 Prometheus') {
                                requestApproval('Prometheus 监控')
                                deployPlaybook('Prometheus 监控', 'playbook/Prometheus/deploy-prometheus.yml')
                                deployPlaybook('Node Exporter', 'playbook/Prometheus/deploy-node-exporter-all.yml')
                                deployPlaybook('Prometheus 配置更新', 'playbook/Prometheus/update-prometheus-config.yml')
                            }
                        }
                        
                        if (params.DEPLOY_GRAFANA) {
                            stage('部署 Grafana') {
                                requestApproval('Grafana 可视化')
                                deployPlaybook('Grafana 可视化', 'playbook/Grafana/deploy-grafana.yml')
                            }
                        }
                        
                        if (params.DEPLOY_GITLAB) {
                            stage('部署 GitLab') {
                                requestApproval('GitLab 代码仓库')
                                deployPlaybook('GitLab 代码仓库', 'playbook/GitLab/deploy-gitlab.yml')
                            }
                        }
                        
                        if (params.DEPLOY_JENKINS) {
                            stage('部署 Jenkins') {
                                requestApproval('Jenkins CI/CD')
                                deployPlaybook('Jenkins CI/CD', 'playbook/Jenkins/deploy-jenkins.yml')
                            }
                        }
                        
                        if (params.DEPLOY_REDIS) {
                            stage('部署 Redis') {
                                requestApproval('Redis 集群')
                                deployPlaybook('Redis 集群', 'playbook/Redis/deploy-redis-cluster.yml')
                            }
                        }
                        
                        if (params.DEPLOY_MYSQL) {
                            stage('部署 MySQL') {
                                requestApproval('MySQL 数据库')
                                deployPlaybook('MySQL 数据库', 'playbook/MySQL/deploy-mysql.yml')
                            }
                        }
                        
                        if (params.DEPLOY_MONGODB) {
                            stage('部署 MongoDB') {
                                requestApproval('MongoDB 数据库')
                                deployPlaybook('MongoDB 数据库', 'playbook/MongoDB/deploy-mongodb.yml')
                            }
                        }
                        
                        if (params.DEPLOY_ELASTICSEARCH) {
                            stage('部署 ElasticSearch') {
                                requestApproval('ElasticSearch 搜索引擎')
                                deployPlaybook('ElasticSearch 搜索引擎', 'playbook/ElasticSearch/deploy-elasticsearch.yml')
                            }
                        }
                        
                        if (params.DEPLOY_KAFKA) {
                            stage('部署 Kafka') {
                                requestApproval('Kafka 消息队列')
                                deployPlaybook('Kafka 消息队列', 'playbook/Kafka/deploy-kafka.yml')
                            }
                        }
                    }
                }
            }
        }
        
        stage('验证部署') {
            steps {
                echo "验证所有服务状态..."
                withCredentials([sshUserPrivateKey(credentialsId: 'ansible-control-node-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            echo "=========================================="
                            echo "验证主机连通性"
                            echo "=========================================="
                            ansible all -i inventory/hosts.ini -m ping | grep -E "SUCCESS|FAILED" || true
                            echo ""
                            echo "=========================================="
                            echo "部署完成"
                            echo "=========================================="
                        '
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo "=========================================="
            echo "✅ 部署流水线执行完成！"
            echo "=========================================="
            script {
                def deployed = []
                if (params.DEPLOY_KUBERNETES) deployed.add("Kubernetes")
                if (params.DEPLOY_PROMETHEUS) deployed.add("Prometheus")
                if (params.DEPLOY_GRAFANA) deployed.add("Grafana")
                if (params.DEPLOY_GITLAB) deployed.add("GitLab")
                if (params.DEPLOY_JENKINS) deployed.add("Jenkins")
                if (params.DEPLOY_REDIS) deployed.add("Redis")
                if (params.DEPLOY_MYSQL) deployed.add("MySQL")
                if (params.DEPLOY_MONGODB) deployed.add("MongoDB")
                if (params.DEPLOY_ELASTICSEARCH) deployed.add("ElasticSearch")
                if (params.DEPLOY_KAFKA) deployed.add("Kafka")
                
                echo "已部署组件: ${deployed.join(', ')}"
                echo ""
                echo "提示: 请查看各组件的具体部署状态"
            }
        }
        unstable {
            echo "=========================================="
            echo "⚠️  部分组件部署失败或被中止"
            echo "=========================================="
            echo "请查看上方日志，检查哪些组件部署失败"
            echo "成功的组件不受影响"
        }
        failure {
            echo "=========================================="
            echo "❌ 部署流水线执行失败！"
            echo "=========================================="
            echo "请查看上方日志获取详细错误信息"
        }
        always {
            echo "清理工作区..."
            cleanWs()
        }
    }
}

// 辅助函数：请求手动批准
def requestApproval(String componentName) {
    if (params.REQUIRE_APPROVAL) {
        echo "⏸️  等待批准部署: ${componentName}"
        input(
            message: "是否继续部署 ${componentName}？",
            ok: "批准部署",
            submitter: 'admin',
            parameters: [
                text(
                    name: 'APPROVAL_COMMENT',
                    defaultValue: '',
                    description: '批准备注（可选）'
                )
            ]
        )
        echo "✅ 已批准部署: ${componentName}"
    }
}

// 辅助函数：部署单个 playbook
def deployPlaybook(String name, String playbookPath) {
    echo "→ 开始部署: ${name}"
    withCredentials([sshUserPrivateKey(credentialsId: 'ansible-control-node-ssh', keyFileVariable: 'SSH_KEY')]) {
        sh """
            ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no ${env.ANSIBLE_USER}@${env.ANSIBLE_CONTROL_NODE} '
                cd ${env.ANSIBLE_PROJECT_DIR}
                echo "================================================"
                echo "部署: ${name}"
                echo "Playbook: ${playbookPath}"
                echo "================================================"
                ansible-playbook -i inventory/hosts.ini ${playbookPath}
                echo ""
                echo "✓ ${name} 部署完成"
                echo ""
            '
        """
    }
}
