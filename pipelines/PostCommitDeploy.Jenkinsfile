// Jenkins Pipeline 配置
// 文件: Jenkinsfile

pipeline {
    agent any
    
    environment {
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_FORCE_COLOR = 'True'
    }
    
    stages {
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
                sh 'ansible-playbook -i inventory/hosts.ini playbook/kubernetes/deploy-k8s-cluster.yml'
            }
        }
        
        stage('部署 GitLab') {
            when {
                expression { env.DEPLOY_GITLAB == 'true' }
            }
            steps {
                echo "部署 GitLab..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml'
            }
        }
        
        stage('部署 Jenkins') {
            when {
                expression { env.DEPLOY_JENKINS == 'true' }
            }
            steps {
                echo "部署 Jenkins..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Jenkins/deploy-jenkins.yml'
            }
        }
        
        stage('部署 Prometheus') {
            when {
                expression { env.DEPLOY_PROMETHEUS == 'true' }
            }
            steps {
                echo "部署 Prometheus 监控..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml'
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-node-exporter-all.yml'
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Prometheus/update-prometheus-config.yml'
            }
        }
        
        stage('部署 Grafana') {
            when {
                expression { env.DEPLOY_GRAFANA == 'true' }
            }
            steps {
                echo "部署 Grafana..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Grafana/deploy-grafana.yml'
            }
        }
        
        stage('部署 Redis') {
            when {
                expression { env.DEPLOY_REDIS == 'true' }
            }
            steps {
                echo "部署 Redis 集群..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Redis/deploy-redis-cluster.yml'
            }
        }
        
        stage('部署 MySQL') {
            when {
                expression { env.DEPLOY_MYSQL == 'true' }
            }
            steps {
                echo "部署 MySQL..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/MySQL/deploy-mysql.yml'
            }
        }
        
        stage('部署 MongoDB') {
            when {
                expression { env.DEPLOY_MONGODB == 'true' }
            }
            steps {
                echo "部署 MongoDB..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/MongoDB/deploy-mongodb.yml'
            }
        }
        
        stage('部署 ElasticSearch') {
            when {
                expression { env.DEPLOY_ELASTICSEARCH == 'true' }
            }
            steps {
                echo "部署 ElasticSearch..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/ElasticSearch/deploy-elasticsearch.yml'
            }
        }
        
        stage('部署 Kafka') {
            when {
                expression { env.DEPLOY_KAFKA == 'true' }
            }
            steps {
                echo "部署 Kafka..."
                sh 'ansible-playbook -i inventory/hosts.ini playbook/Kafka/deploy-kafka.yml'
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
