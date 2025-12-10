
# DevOps 基础设施自动化部署

本项目使用 Ansible 自动化部署完整的 DevOps 基础设施，包括 Kubernetes 高可用集群、GitLab、Jenkins、Prometheus 监控、Grafana 可视化、Redis 集群和 MySQL 数据库。

## 基础设施架构

### Ansible 控制节点
- **控制节点**: 192.168.31.132
- **HTTP 代理**: 192.168.31.132:20171

### Kubernetes 高可用集群
- **主节点**:
  - KubernetesMaster000 (192.168.31.30)
  - KubernetesMaster001 (192.168.31.31)
- **工作节点**:
  - KubernetesWorker000 (192.168.31.40)
  - KubernetesWorker001 (192.168.31.41)
  - KubernetesWorker002 (192.168.31.42)
  - KubernetesWorker003 (192.168.31.43)
- **高可用 VIP**: 192.168.31.100 (kube-vip v0.8.7)
- **Kubernetes 版本**: v1.31.3
- **容器运行时**: containerd
- **CNI 插件**: Calico v3.29.1

### 应用服务
- **GitLab CE**: 192.168.31.50 (v17.6.1)
- **Jenkins LTS**: 192.168.31.70 (v2.528.2)
- **Grafana Enterprise**: 192.168.31.60 (v12.3.0)

### 监控系统
- **Prometheus**: 192.168.31.80 (v3.8.0)
- **Node Exporter**: v1.10.2 (部署在所有 18 台虚拟机)
- **监控目标**: 37 个 (18 个唯一节点 + 各类服务)
- **监控面板**: Grafana 集成，显示节点名称和 IP

### 数据存储
- **Redis 集群**: 
  - Redis000-002 (192.168.31.90-92)
  - 版本: Redis 8.3.240 (stable)
  - 模式: 3 主节点集群，无密码认证
  
- **MySQL**: 
  - MySQL (192.168.31.110)
  - 版本: MySQL 8.0
  - 认证: 无密码登录
  
- **MongoDB**:
  - MongoDB (192.168.31.140)
  - 版本: MongoDB 8.0
  
- **ElasticSearch**:
  - ElasticSearch (192.168.31.150)
  - 版本: 8.19.8
  - 认证: 无密码访问

### 消息队列
- **Kafka**: 192.168.31.120
- **RocketMQ**: 192.168.31.130

## 前置条件

1. 所有虚拟机已安装 Ubuntu 24.04 操作系统
2. Ansible 控制节点可以通过 SSH 免密登录所有节点
3. 所有节点通过代理访问互联网 (http://192.168.31.132:20171)
4. 各节点具有足够的资源：
   - Kubernetes 节点: 至少 2 CPU, 4GB RAM
   - GitLab: 至少 4GB RAM (推荐 8GB)
   - Jenkins: 至少 2GB RAM (推荐 4GB)
   - Prometheus/Grafana: 至少 2GB RAM
   - Redis/MySQL: 至少 1GB RAM

## SSH 密钥配置

在控制节点上执行：

```bash
# 生成 SSH 密钥（如果没有）
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# 复制密钥到所有节点
for ip in 192.168.31.{30,31,40,41,42,43,50,60,70,80,90,91,92,110,120,130,140,150}; do
  ssh-copy-id node@$ip
done
```

## 快速部署

### 1. Kubernetes 集群
```bash
ansible-playbook -i inventory/hosts.ini playbook/kubernetes/deploy-k8s-cluster.yml
```

### 2. GitLab
```bash
ansible-playbook -i inventory/hosts.ini playbook/GitLab/deploy-gitlab.yml
```

### 3. Jenkins
```bash
ansible-playbook -i inventory/hosts.ini playbook/Jenkins/deploy-jenkins.yml
```

### 4. Prometheus 监控
```bash
# 部署 Prometheus
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-prometheus.yml

# 在所有节点部署 Node Exporter
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/deploy-node-exporter-all.yml

# 更新 Prometheus 配置
ansible-playbook -i inventory/hosts.ini playbook/Prometheus/update-prometheus-config.yml
```

### 5. Grafana
```bash
ansible-playbook -i inventory/hosts.ini playbook/Grafana/deploy-grafana.yml
```

### 6. Redis 集群
```bash
ansible-playbook -i inventory/hosts.ini playbook/Redis/deploy-redis-cluster.yml
```

### 7. MySQL
```bash
ansible-playbook -i inventory/hosts.ini playbook/MySQL/deploy-mysql.yml
```

### 8. MongoDB
```bash
ansible-playbook -i inventory/hosts.ini playbook/MongoDB/deploy-mongodb.yml
```

### 9. ElasticSearch
```bash
ansible-playbook -i inventory/hosts.ini playbook/ElasticSearch/deploy-elasticsearch.yml
```

## 服务访问信息

### Kubernetes
- API Server: https://192.168.31.100:6443
- kubeconfig: 在主节点 `/etc/kubernetes/admin.conf`

### GitLab
- URL: http://192.168.31.50
- 用户名: root
- 初始密码: 登录服务器查看 `sudo cat /etc/gitlab/initial_root_password`

### Jenkins
- URL: http://192.168.31.70:8080
- 初始密码: 登录服务器查看 `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`

### Grafana
- URL: http://192.168.31.60:3000
- 默认用户名/密码: admin/admin
- 仪表板: 所有节点监控概览 (18 个节点)

### Prometheus
- URL: http://192.168.31.80:9090
- 监控目标: http://192.168.31.80:9090/targets

### Redis 集群
- 节点: 192.168.31.90-92:6379
- 认证: 无需密码
- 连接: `redis-cli -c -h 192.168.31.90`

### MySQL
- 主机: 192.168.31.110:3306
- 用户: root
- 密码: 无需密码
- 连接: `mysql -h 192.168.31.110 -u root`

### MongoDB
- 主机: 192.168.31.140:27017
- 连接: `mongosh mongodb://192.168.31.140:27017`

### ElasticSearch
- URL: http://192.168.31.150:9200
- 认证: 无需密码
- 健康检查: `curl http://192.168.31.150:9200/_cluster/health?pretty`

## 详细文档

- [Kubernetes 部署](playbook/kubernetes/README.md)
- [GitLab 部署](playbook/GitLab/README.md)
- [Jenkins 部署](playbook/Jenkins/README.md)
- [Prometheus 监控](playbook/Prometheus/README.md)
- [Grafana 可视化](playbook/Grafana/README.md)
- [Redis 集群](playbook/Redis/README.md)
- [MySQL 数据库](playbook/MySQL/README.md)
- [MongoDB 数据库](playbook/MongoDB/README.md)
- [ElasticSearch 搜索引擎](playbook/ElasticSearch/README.md)

## 验证部署

### Kubernetes 集群验证
```bash
# 查看节点状态
ansible kubernetes_first_master -i inventory/hosts.ini -m shell -a "kubectl get nodes -o wide"

# 查看所有 pods
ansible kubernetes_first_master -i inventory/hosts.ini -m shell -a "kubectl get pods -A"

# 验证高可用 VIP
ping 192.168.31.100
curl -k https://192.168.31.100:6443/healthz
```

### 监控系统验证
```bash
# Prometheus 目标检查
curl http://192.168.31.80:9090/api/v1/targets

# Grafana 访问
curl http://192.168.31.60:3000
```

### Redis 集群验证
```bash
ssh node@192.168.31.90 "/opt/redis/bin/redis-cli cluster info"
```

### MySQL 验证
```bash
ssh node@192.168.31.110 "mysql -u root -e 'SELECT VERSION();'"
```

## 重要配置说明

### 网络接口配置

如果您的虚拟机网络接口不是 `eth0`，需要修改：

```bash
# 在每个节点上查看网络接口名称
ip addr show

# 然后修改 group_vars/all.yml 中的配置
kube_vip_interface: "ens33"  # 或其他接口名称
```

### 代理配置

如果您的代理地址不同，修改以下文件：
- `group_vars/all.yml`
- `inventory/hosts.ini`

### Kubernetes 版本

在 `group_vars/all.yml` 中可以修改 Kubernetes 版本：

```yaml
kubernetes_version: "1.28.2"
```

## 常见问题处理

### 1. 节点无法加入集群

```bash
# 在主节点重新生成 join 命令
kubeadm token create --print-join-command

# 对于主节点加入
kubeadm token create --print-join-command --certificate-key $(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
```

### 2. kube-vip 未启动

```bash
# 检查 kube-vip pod
kubectl get pods -n kube-system -l component=kube-vip

# 查看日志
kubectl logs -n kube-system <kube-vip-pod-name>

# 验证网络接口配置
ip addr show
```

### 3. containerd 问题

```bash
# 重启 containerd
systemctl restart containerd

# 查看日志
journalctl -xeu containerd

# 验证 containerd 配置
crictl info
```

### 4. 清理集群并重新部署

```bash
# 在所有节点上执行
ansible k8s_cluster -m shell -a "kubeadm reset -f"
ansible k8s_cluster -m shell -a "rm -rf /etc/cni/net.d /etc/kubernetes /var/lib/etcd /var/lib/kubelet"
ansible k8s_cluster -m shell -a "systemctl restart containerd"

# 然后重新运行 playbook
ansible-playbook playbook/deploy-k8s-cluster.yml
```

## 访问集群

### 从控制节点访问

```bash
# 获取 kubeconfig
scp node@192.168.31.30:/etc/kubernetes/admin.conf ~/.kube/config

# 配置代理（如果需要）
export HTTPS_PROXY=http://192.168.31.132:20171
export NO_PROXY=192.168.31.0/24,10.96.0.0/12,10.244.0.0/16

# 使用 kubectl
kubectl get nodes
kubectl get pods -A
```

## 后续操作

### 安装 Kubernetes Dashboard

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### 安装 Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 配置 MetalLB 负载均衡器

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

## 项目结构

```
ansible/
├── ansible.cfg                      # Ansible 配置文件
├── deploy.sh                        # 快速部署脚本
├── README.md                        # 项目说明文档
├── .gitignore                       # Git 忽略文件配置
├── inventory/
│   └── hosts.ini                    # 主机清单
├── group_vars/
│   └── all.yml                      # 全局变量
├── logs/                            # 日志目录 (gitignore)
│   └── kubernetes/
└── playbook/
    ├── kubernetes/                  # Kubernetes 集群
    │   ├── deploy-k8s-cluster.yml
    │   ├── 01-system-prepare.yml
    │   ├── 02-install-containerd.yml
    │   ├── 03-install-kubernetes.yml
    │   ├── 04-install-kube-vip.yml
    │   ├── 05-init-kubernetes-master.yml
    │   ├── 06-join-kubernetes-master.yml
    │   ├── 07-join-kubernetes-worker.yml
    │   ├── 08-install-cni.yml
    │   ├── 09-verify-cluster.yml
    │   ├── README.md
    │   └── roles/
    │       ├── system-prepare/
    │       ├── install-containerd/
    │       ├── install-kubernetes/
    │       ├── install-kube-vip/
    │       ├── init-kubernetes-master/
    │       ├── join-kubernetes-master/
    │       ├── join-kubernetes-worker/
    │       └── install-cni/
    ├── GitLab/                      # GitLab CE
    │   ├── deploy-gitlab.yml
    │   ├── upgrade-gitlab.yml
    │   ├── upgrade-step.yml
    │   ├── README.md
    │   ├── UPGRADE.md
    │   └── roles/install-gitlab/
    ├── Jenkins/                     # Jenkins LTS
    │   ├── deploy-jenkins.yml
    │   ├── README.md
    │   └── roles/install-jenkins/
    ├── Prometheus/                  # Prometheus 监控
    │   ├── deploy-prometheus.yml
    │   ├── deploy-node-exporter-all.yml
    │   ├── update-prometheus-config.yml
    │   ├── prometheus-updated.yml.j2
    │   ├── README.md
    │   └── roles/install-prometheus/
    ├── Grafana/                     # Grafana 可视化
    │   ├── deploy-grafana.yml
    │   ├── update-dashboards.yml
    │   ├── README.md
    │   └── roles/install-grafana/
    ├── Redis/                       # Redis 集群
    │   ├── deploy-redis-cluster.yml
    │   ├── README.md
    │   └── roles/install-redis-cluster/
    ├── MySQL/                       # MySQL 数据库
    │   ├── deploy-mysql.yml
    │   ├── README.md
    │   └── roles/install-mysql/
    ├── MongoDB/                     # MongoDB 数据库
    │   ├── deploy-mongodb.yml
    │   ├── README.md
    │   └── roles/install-mongodb/
    ├── ElasticSearch/              # ElasticSearch 搜索引擎
    │   ├── deploy-elasticsearch.yml
    │   ├── README.md
    │   └── roles/install-elasticsearch/
    └── Kafka/                       # Kafka 消息队列
        ├── deploy-kafka.yml
        └── roles/install-kafka/
```

## 支持

如有问题,请检查:
1. Ansible 执行日志
2. `/var/log/syslog` 或 `/var/log/messages`
3. `journalctl -xeu kubelet`
4. `kubectl logs` 查看 pod 日志
