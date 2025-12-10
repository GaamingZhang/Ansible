// Jenkins Pipeline 配置
// 文件: PostCommitDeploy.Jenkinsfile
// 说明: 通过 SSH 连接到 Ansible 控制节点执行部署

pipeline {
    agent any
    
    environment {
        ANSIBLE_CONTROL_NODE = '192.168.31.10'
        ANSIBLE_USER = 'node'
        ANSIBLE_PROJECT_DIR = '/home/node/ansible'
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_FORCE_COLOR = 'True'
    }
    
    stages {
        stage('连接 Ansible 控制节点') {
            steps {
                echo "=========================================="
                echo "连接到 Ansible 控制节点: ${ANSIBLE_CONTROL_NODE}"
                echo "用户: ${ANSIBLE_USER}"
                echo "项目目录: ${ANSIBLE_PROJECT_DIR}"
                echo "=========================================="
                
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            echo "成功连接到 Ansible 控制节点"
                            hostname
                            whoami
                            ansible --version
                        '
                    """
                }
            }
        }
        
        stage('检测变更') {
            steps {
                script {
                    echo "检测哪些 playbook 被修改..."
                    
                    def changedFiles = sh(
                        script: 'git diff --name-only HEAD~1 HEAD || echo ""',
                        returnStdout: true
                    ).trim()
                    
                    echo "变更的文件:\n${changedFiles}"
                    
                    // 设置部署标志
                    env.DEPLOY_KUBERNETES = changedFiles.contains('playbook/kubernetes/') ? 'true' : 'false'
                    env.DEPLOY_GITLAB = changedFiles.contains('playbook/GitLab/') ? 'true' : 'false'
                    env.DEPLOY_JENKINS = changedFiles.contains('playbook/Jenkins/') ? 'true' : 'false'
                    env.DEPLOY_PROMETHEUS = changedFiles.contains('playbook/Prometheus/') ? 'true' : 'false'
                    env.DEPLOY_GRAFANA = changedFiles.contains('playbook/Grafana/') ? 'true' : 'false'
                    env.DEPLOY_REDIS = changedFiles.contains('playbook/Redis/') ? 'true' : 'false'
                    env.DEPLOY_MYSQL = changedFiles.contains('playbook/MySQL/') ? 'true' : 'false'
                    env.DEPLOY_MONGODB = changedFiles.contains('playbook/MongoDB/') ? 'true' : 'false'
                    env.DEPLOY_ELASTICSEARCH = changedFiles.contains('playbook/ElasticSearch/') ? 'true' : 'false'
                    env.DEPLOY_KAFKA = changedFiles.contains('playbook/Kafka/') ? 'true' : 'false'
                }
            }
        }
        
        stage('部署 Kubernetes') {
            when {
                expression { env.DEPLOY_KUBERNETES == 'true' }
            }
            steps {
                echo "部署 Kubernetes 集群..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/kubernetes/deploy-k8s-cluster.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 GitLab') {
            when {
                expression { env.DEPLOY_GITLAB == 'true' }
            }
            steps {
                echo "部署 GitLab..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 Jenkins') {
            when {
                expression { env.DEPLOY_JENKINS == 'true' }
            }
            steps {
                echo "部署 Jenkins..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/Jenkins/deploy-jenkins.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 Prometheus') {
            when {
                expression { env.DEPLOY_PROMETHEUS == 'true' }
            }
            steps {
                echo "部署 Prometheus 监控..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml
                            ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-node-exporter-all.yml
                            ansible-playbook -i inventory/hosts.ini playbook/Prometheus/update-prometheus-config.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 Grafana') {
            when {
                expression { env.DEPLOY_GRAFANA == 'true' }
            }
            steps {
                echo "部署 Grafana..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/Grafana/deploy-grafana.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 Redis') {
            when {
                expression { env.DEPLOY_REDIS == 'true' }
            }
            steps {
                echo "部署 Redis 集群..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/Redis/deploy-redis-cluster.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 MySQL') {
            when {
                expression { env.DEPLOY_MYSQL == 'true' }
            }
            steps {
                echo "部署 MySQL..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/MySQL/deploy-mysql.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 MongoDB') {
            when {
                expression { env.DEPLOY_MONGODB == 'true' }
            }
            steps {
                echo "部署 MongoDB..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/MongoDB/deploy-mongodb.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 ElasticSearch') {
            when {
                expression { env.DEPLOY_ELASTICSEARCH == 'true' }
            }
            steps {
                echo "部署 ElasticSearch..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/ElasticSearch/deploy-elasticsearch.yml
                        '
                    """
                }
            }
        }
        
        stage('部署 Kafka') {
            when {
                expression { env.DEPLOY_KAFKA == 'true' }
            }
            steps {
                echo "部署 Kafka..."
                sshagent(['ansible-control-node-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${ANSIBLE_USER}@${ANSIBLE_CONTROL_NODE} '
                            cd ${ANSIBLE_PROJECT_DIR}
                            git pull origin main
                            ansible-playbook -i inventory/hosts.ini playbook/Kafka/deploy-kafka.yml
                        '
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo '✅ 部署成功!'
        }
        failure {
            echo '❌ 部署失败!'
        }
        always {
            echo '清理工作区...'
            cleanWs()
        }
    }
}
