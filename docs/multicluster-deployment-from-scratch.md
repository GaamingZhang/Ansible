# Kubernetes多集群从零部署完整指南

## 目录

1. [架构规划](#1-架构规划)
2. [阶段一：现有集群清理](#2-阶段一现有集群清理)
3. [阶段二：集群1部署](#3-阶段二集群1部署)
4. [阶段三：集群2部署](#4-阶段三集群2部署)
5. [阶段四：基础设施组件部署](#5-阶段四基础设施组件部署)
6. [阶段五：双环境应用部署](#6-阶段五双环境应用部署)
7. [阶段六：CI/CD流水线配置](#7-阶段六cicd流水线配置)
8. [阶段七：监控和可观测性](#8-阶段七监控和可观测性)
9. [阶段八：验证和测试](#9-阶段八验证和测试)

---

## 1. 架构规划

### 1.1 当前状态

**现有集群**：
- Master节点：192.168.31.30, 192.168.31.31
- Worker节点：192.168.31.40, 192.168.31.41, 192.168.31.42, 192.168.31.43
- 集群状态：单一集群，高可用Master

### 1.2 目标架构

**集群1 - Cluster1**：
- Master节点：192.168.31.30 (cluster1-master)
- Worker节点：
  - 192.168.31.40 (cluster1-worker1)
  - 192.168.31.41 (cluster1-worker2)
- VIP：192.168.31.100
- Pod CIDR：10.244.1.0/16
- Service CIDR：10.96.1.0/12

**集群2 - Cluster2**：
- Master节点：192.168.31.31 (cluster2-master)
- Worker节点：
  - 192.168.31.42 (cluster2-worker1)
  - 192.168.31.43 (cluster2-worker2)
- VIP：192.168.31.101
- Pod CIDR：10.244.2.0/16
- Service CIDR：10.96.2.0/12

### 1.3 环境规划

每个集群都部署两个环境：
- **gaamingblog-prod**：生产环境
- **gaamingblog-canary**：开发环境

---

## 2. 阶段一：现有集群清理

### 2.1 备份重要数据

```bash
# 在主节点执行
# 1. 备份kubectl配置
cp -r ~/.kube ~/.kube.backup

# 2. 备份重要的ConfigMap和Secret
kubectl get configmap -A -o yaml > /tmp/configmaps-backup.yaml
kubectl get secret -A -o yaml > /tmp/secrets-backup.yaml

# 3. 备份PV和PVC信息
kubectl get pv -o yaml > /tmp/pv-backup.yaml
kubectl get pvc -A -o yaml > /tmp/pvc-backup.yaml

# 4. 备份当前集群信息
kubectl cluster-info dump > /tmp/cluster-info-backup.txt

# 5. 保存到安全位置
tar -czf k8s-backup-$(date +%Y%m%d).tar.gz /tmp/*backup* ~/.kube.backup
```

### 2.2 清理Worker节点

```bash
# 在每个Worker节点执行
# Worker节点：192.168.31.40, 192.168.31.41, 192.168.31.42, 192.168.31.43

# 1. 驱逐Pod（在Master节点执行）
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 2. 删除节点（在Master节点执行）
kubectl delete node <node-name>

# 3. 在Worker节点上重置Kubernetes
ssh root@192.168.31.40 << 'EOF'
kubeadm reset -f
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/dockershim/
rm -rf /var/lib/etcd/
rm -rf /var/lib/cni/
rm -rf /etc/cni/
rm -rf /root/.kube/config
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
EOF

# 对其他Worker节点重复执行
for ip in 192.168.31.41 192.168.31.42 192.168.31.43; do
  ssh root@$ip << 'EOF'
kubeadm reset -f
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/dockershim/
rm -rf /var/lib/etcd/
rm -rf /var/lib/cni/
rm -rf /etc/cni/
rm -rf /root/.kube/config
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
EOF
done
```

### 2.3 清理Master节点

```bash
# 在两个Master节点执行
# Master节点：192.168.31.30, 192.168.31.31

for ip in 192.168.31.30 192.168.31.31; do
  ssh root@$ip << 'EOF'
# 重置Kubernetes
kubeadm reset -f

# 清理所有配置文件
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/dockershim/
rm -rf /var/lib/etcd/
rm -rf /var/lib/cni/
rm -rf /etc/cni/
rm -rf /root/.kube/config

# 清理iptables
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

# 清理containerd（可选）
# systemctl stop containerd
# rm -rf /var/lib/containerd/*
# systemctl start containerd
EOF
done
```

### 2.4 验证清理完成

```bash
# 检查所有节点
for ip in 192.168.31.30 192.168.31.31 192.168.31.40 192.168.31.41 192.168.31.42 192.168.31.43; do
  echo "=== Checking $ip ==="
  ssh root@$ip 'systemctl status kubelet || echo "kubelet not running"'
  ssh root@$ip 'ls -la /etc/kubernetes/ 2>/dev/null || echo "kubernetes dir cleaned"'
done
```

---

## 3. 阶段二：集群1部署

### 3.1 更新Ansible Inventory

```bash
# 编辑inventory文件
cat > inventory/hosts.ini << 'EOF'
[allNodes:children]
cluster1
cluster2
gitlab_server
jenkins_server
prometheus_server
grafana_server
mysql_server
mongodb_server

# 集群1
[cluster1:children]
cluster1_masters
cluster1_workers

[cluster1_masters]
Cluster1Master ansible_host=192.168.31.30

[cluster1_workers]
Cluster1Worker1 ansible_host=192.168.31.40
Cluster1Worker2 ansible_host=192.168.31.41

[cluster1_first_master]
Cluster1Master ansible_host=192.168.31.30

# 集群2
[cluster2:children]
cluster2_masters
cluster2_workers

[cluster2_masters]
Cluster2Master ansible_host=192.168.31.31

[cluster2_workers]
Cluster2Worker1 ansible_host=192.168.31.42
Cluster2Worker2 ansible_host=192.168.31.43

[cluster2_first_master]
Cluster2Master ansible_host=192.168.31.31

# CI/CD组件
[gitlab_server]
GitLab ansible_host=192.168.31.50

[jenkins_server]
Jenkins ansible_host=192.168.31.70

# 监控组件
[prometheus_server]
Prometheus ansible_host=192.168.31.80

[grafana_server]
Grafana ansible_host=192.168.31.60

# 数据库
[mysql_server]
MySQL ansible_host=192.168.31.110

[mongodb_server]
MongoDB ansible_host=192.168.31.140
EOF
```

### 3.2 创建集群1变量文件

```bash
# 创建集群1的变量文件
cat > group_vars/cluster1.yml << 'EOF'
---
# Kubernetes集群配置
kubernetes_cluster_name: "cluster1"
kubernetes_version: "1.31.3"
kubernetes_pod_network_cidr: "10.244.1.0/16"
kubernetes_service_cidr: "10.96.1.0/12"

# kube-vip配置
kube_vip_vip: "192.168.31.100"
kube_vip_interface: "ens33"

# containerd配置
containerd_version: "1.7.22"

# CNI配置
cni_type: "calico"
calico_version: "3.29.1"

# 节点标签
node_labels:
  cluster: cluster1
  environment: production
EOF
```

### 3.3 部署集群1

```bash
# 在Ansible控制节点执行
cd /Users/gaamingzhang/jiazhang/ansible

# 1. 系统准备
ansible-playbook playbook/kubernetes/01-system-prepare.yml -l cluster1

# 2. 安装containerd
ansible-playbook playbook/kubernetes/02-install-containerd.yml -l cluster1

# 3. 安装Kubernetes组件
ansible-playbook playbook/kubernetes/03-install-kubernetes.yml -l cluster1

# 4. 安装kube-vip
ansible-playbook playbook/kubernetes/04-install-kube-vip.yml -l cluster1

# 5. 初始化Master节点
ansible-playbook playbook/kubernetes/05-init-kubernetes-master.yml -l cluster1_first_master

# 6. Worker节点加入集群
ansible-playbook playbook/kubernetes/07-join-kubernetes-worker.yml -l cluster1_workers

# 7. 安装CNI
ansible-playbook playbook/kubernetes/08-install-cni.yml -l cluster1_first_master

# 8. 验证集群
ansible-playbook playbook/kubernetes/09-verify-cluster.yml -l cluster1_first_master
```

### 3.4 验证集群1

```bash
# 获取集群1的kubeconfig
ssh root@192.168.31.30 'cat /etc/kubernetes/admin.conf' > ~/.kube/config.cluster1

# 设置上下文
export KUBECONFIG=~/.kube/config.cluster1
kubectl config rename-context kubernetes-admin@kubernetes cluster1
kubectl config use-context cluster1

# 验证节点
kubectl get nodes -o wide

# 验证组件
kubectl get pods -n kube-system

# 验证网络
kubectl get pods -n kube-system | grep calico
```

---

## 4. 阶段三：集群2部署

### 4.1 创建集群2变量文件

```bash
# 创建集群2的变量文件
cat > group_vars/cluster2.yml << 'EOF'
---
# Kubernetes集群配置
kubernetes_cluster_name: "cluster2"
kubernetes_version: "1.31.3"
kubernetes_pod_network_cidr: "10.244.2.0/16"
kubernetes_service_cidr: "10.96.2.0/12"

# kube-vip配置
kube_vip_vip: "192.168.31.101"
kube_vip_interface: "ens33"

# containerd配置
containerd_version: "1.7.22"

# CNI配置
cni_type: "calico"
calico_version: "3.29.1"

# 节点标签
node_labels:
  cluster: cluster2
  environment: production
EOF
```

### 4.2 部署集群2

```bash
# 在Ansible控制节点执行
cd /Users/gaamingzhang/jiazhang/ansible

# 1. 系统准备
ansible-playbook playbook/kubernetes/01-system-prepare.yml -l cluster2

# 2. 安装containerd
ansible-playbook playbook/kubernetes/02-install-containerd.yml -l cluster2

# 3. 安装Kubernetes组件
ansible-playbook playbook/kubernetes/03-install-kubernetes.yml -l cluster2

# 4. 安装kube-vip
ansible-playbook playbook/kubernetes/04-install-kube-vip.yml -l cluster2

# 5. 初始化Master节点
ansible-playbook playbook/kubernetes/05-init-kubernetes-master.yml -l cluster2_first_master

# 6. Worker节点加入集群
ansible-playbook playbook/kubernetes/07-join-kubernetes-worker.yml -l cluster2_workers

# 7. 安装CNI
ansible-playbook playbook/kubernetes/08-install-cni.yml -l cluster2_first_master

# 8. 验证集群
ansible-playbook playbook/kubernetes/09-verify-cluster.yml -l cluster2_first_master
```

### 4.3 验证集群2

```bash
# 获取集群2的kubeconfig
ssh root@192.168.31.31 'cat /etc/kubernetes/admin.conf' > ~/.kube/config.cluster2

# 设置上下文
export KUBECONFIG=~/.kube/config.cluster2
kubectl config rename-context kubernetes-admin@kubernetes cluster2
kubectl config use-context cluster2

# 验证节点
kubectl get nodes -o wide

# 验证组件
kubectl get pods -n kube-system
```

### 4.4 配置多集群访问

```bash
# 合并kubeconfig文件
export KUBECONFIG=~/.kube/config.cluster1:~/.kube/config.cluster2

# 查看所有上下文
kubectl config get-contexts

# 切换到集群1
kubectl config use-context cluster1

# 切换到集群2
kubectl config use-context cluster2

# 保存合并后的配置
kubectl config view --flatten > ~/.kube/config
```

---

## 5. 阶段四：基础设施组件部署

### 5.1 部署Harbor镜像仓库

#### 5.1.1 在集群1部署Harbor

```bash
# 切换到集群1
kubectl config use-context cluster1

# 创建Harbor Namespace
kubectl create namespace harbor

# 使用Helm部署Harbor
helm repo add harbor https://helm.goharbor.io
helm repo update

helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.nodePort.ports.https.nodePort=30003 \
  --set externalURL=https://192.168.31.30:30003 \
  --set harborAdminPassword="Harbor12345" \
  --set persistence.persistentVolumeClaim.registry.size=50Gi \
  --set persistence.persistentVolumeClaim.database.size=10Gi

# 等待Harbor就绪
kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=600s

# 访问Harbor
# https://192.168.31.30:30003
# 用户名：admin
# 密码：Harbor12345
```

#### 5.1.2 在集群2部署Harbor

```bash
# 切换到集群2
kubectl config use-context cluster2

# 创建Harbor Namespace
kubectl create namespace harbor

# 使用Helm部署Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.nodePort.ports.https.nodePort=30003 \
  --set externalURL=https://192.168.31.31:30003 \
  --set harborAdminPassword="Harbor12345" \
  --set persistence.persistentVolumeClaim.registry.size=50Gi \
  --set persistence.persistentVolumeClaim.database.size=10Gi

# 等待Harbor就绪
kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=600s

# 访问Harbor
# https://192.168.31.31:30003
```

### 5.2 部署Istio服务网格

#### 5.2.1 在集群1部署Istio

```bash
# 切换到集群1
kubectl config use-context cluster1

# 下载Istio（如果还没下载）
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 创建Istio配置
cat <<EOF > istio-cluster1.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: default
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
    pilot:
      env:
        EXTERNAL_ISTIOD: "true"
EOF

# 安装Istio
istioctl install -f istio-cluster1.yaml -y

# 验证
kubectl get pods -n istio-system
```

#### 5.2.2 在集群2部署Istio

```bash
# 切换到集群2
kubectl config use-context cluster2

# 创建Istio配置
cat <<EOF > istio-cluster2.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: default
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster2
      network: network1
    pilot:
      env:
        EXTERNAL_ISTIOD: "true"
EOF

# 安装Istio
istioctl install -f istio-cluster2.yaml -y

# 验证
kubectl get pods -n istio-system
```

### 5.3 部署ArgoCD

#### 5.3.1 在集群1部署ArgoCD

```bash
# 切换到集群1
kubectl config use-context cluster1

# 创建ArgoCD Namespace
kubectl create namespace argocd

# 部署ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待ArgoCD就绪
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 端口转发访问
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &

# 访问：https://192.168.31.30:8080
```

#### 5.3.2 配置ArgoCD多集群管理

```bash
# 安装ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# 登录ArgoCD
argocd login 192.168.31.30:8080 --grpc-web

# 添加集群2到ArgoCD
argocd cluster add cluster2 --name cluster2 --grpc-web

# 验证集群列表
argocd cluster list
```

### 5.4 部署Ingress-Nginx

#### 5.4.1 在集群1部署Ingress-Nginx

```bash
# 切换到集群1
kubectl config use-context cluster1

# 部署Ingress-Nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# 等待就绪
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 验证
kubectl get svc -n ingress-nginx
```

#### 5.4.2 在集群2部署Ingress-Nginx

```bash
# 切换到集群2
kubectl config use-context cluster2

# 部署Ingress-Nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# 等待就绪
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 验证
kubectl get svc -n ingress-nginx
```

---

## 6. 阶段五：双环境应用部署

### 6.1 创建Namespace和资源配额

#### 6.1.1 在集群1创建双环境

```bash
# 切换到集群1
kubectl config use-context cluster1

# 创建Namespace
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary

# 添加标签
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

# 创建资源配额
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gaamingblog-prod-quota
  namespace: gaamingblog-prod
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gaamingblog-canary-quota
  namespace: gaamingblog-canary
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    pods: "5"
EOF
```

#### 6.1.2 在集群2创建双环境

```bash
# 切换到集群2
kubectl config use-context cluster2

# 创建Namespace
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary

# 添加标签
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

# 创建资源配额（同上）
kubectl apply -f - <<EOF
[使用相同的ResourceQuota配置]
EOF
```

### 6.2 创建Secret

#### 6.2.1 创建数据库Secret

```bash
# 集群1 - 生产环境
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod \
  --context=cluster1

# 集群1 - 开发环境
kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary \
  --context=cluster1

# 集群2 - 重复相同操作
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod \
  --context=cluster2

kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary \
  --context=cluster2
```

#### 6.2.2 创建Harbor Registry Secret

```bash
# 集群1
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod \
  --context=cluster1

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary \
  --context=cluster1

# 集群2
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.31:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod \
  --context=cluster2

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.31:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary \
  --context=cluster2
```

### 6.3 创建GitOps仓库和应用配置

参考之前的 `deployment-guide.md` 文档中的 GitOps 配置部分，创建完整的Helm Chart配置。

---

## 7. 阶段六：CI/CD流水线配置

参考之前的 `deployment-guide.md` 文档中的 CI/CD 配置部分。

---

## 8. 阶段七：监控和可观测性

### 8.1 部署Prometheus

```bash
# 使用Ansible部署Prometheus到集群1
ansible-playbook playbook/Prometheus/deploy-prometheus.yml -l cluster1_first_master

# 部署Node Exporter到集群1所有节点
ansible-playbook playbook/Prometheus/deploy-node-exporter-all.yml -l cluster1

# 对集群2重复相同操作
ansible-playbook playbook/Prometheus/deploy-prometheus.yml -l cluster2_first_master
ansible-playbook playbook/Prometheus/deploy-node-exporter-all.yml -l cluster2
```

### 8.2 部署Grafana

```bash
# 使用Ansible部署Grafana
ansible-playbook playbook/Grafana/deploy-grafana.yml
```

---

## 9. 阶段八：验证和测试

### 9.1 验证集群状态

```bash
# 验证集群1
kubectl config use-context cluster1
kubectl get nodes
kubectl get pods -A

# 验证集群2
kubectl config use-context cluster2
kubectl get nodes
kubectl get pods -A
```

### 9.2 验证应用部署

```bash
# 集群1 - 验证双环境
kubectl config use-context cluster1
kubectl get all -n gaamingblog-prod
kubectl get all -n gaamingblog-canary

# 集群2 - 验证双环境
kubectl config use-context cluster2
kubectl get all -n gaamingblog-prod
kubectl get all -n gaamingblog-canary
```

### 9.3 测试访问

```bash
# 测试生产环境
curl -H "Host: blog.gaaming.com" http://192.168.31.100/health
curl -H "Host: blog.gaaming.com" http://192.168.31.101/health

# 测试开发环境
curl -H "Host: canary.blog.gaaming.com" http://192.168.31.100/health
curl -H "Host: canary.blog.gaaming.com" http://192.168.31.101/health
```

---

## 10. 一键部署脚本

### 10.1 完整部署脚本

```bash
#!/bin/bash
# deploy-multicluster-from-scratch.sh
# 从零开始部署多集群双环境架构

set -e

echo "=== 开始从零部署Kubernetes多集群双环境架构 ==="

# 阶段一：清理现有集群
echo "阶段一：清理现有集群..."
read -p "确认要清理现有集群吗？这将删除所有数据！(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "取消部署"
    exit 1
fi

# 执行清理（参考上面的清理命令）
# ...

# 阶段二：部署集群1
echo "阶段二：部署集群1..."
ansible-playbook playbook/kubernetes/deploy-k8s-cluster.yml -l cluster1

# 阶段三：部署集群2
echo "阶段三：部署集群2..."
ansible-playbook playbook/kubernetes/deploy-k8s-cluster.yml -l cluster2

# 阶段四：配置多集群访问
echo "阶段四：配置多集群访问..."
# 合并kubeconfig
# ...

# 阶段五：部署基础设施组件
echo "阶段五：部署基础设施组件..."
# Harbor, Istio, ArgoCD, Ingress-Nginx
# ...

# 阶段六：部署双环境应用
echo "阶段六：部署双环境应用..."
# 创建Namespace, Secret, GitOps配置
# ...

# 阶段七：部署监控
echo "阶段七：部署监控..."
# Prometheus, Grafana
# ...

echo "=== 部署完成 ==="
echo "集群1 API: https://192.168.31.100:6443"
echo "集群2 API: https://192.168.31.101:6443"
echo "ArgoCD: https://192.168.31.30:8080"
```

---

## 11. 总结

### 11.1 部署时间估算

- **阶段一：清理现有集群**：30分钟
- **阶段二：部署集群1**：1小时
- **阶段三：部署集群2**：1小时
- **阶段四：基础设施组件**：2小时
- **阶段五：双环境应用**：1小时
- **阶段六：CI/CD流水线**：1小时
- **阶段七：监控部署**：1小时
- **阶段八：验证测试**：1小时
- **总计**：约8-9小时

### 11.2 最终架构

**集群1**：
- 1 Master + 2 Worker
- 双环境：gaamingblog-prod, gaamingblog-canary
- 组件：Harbor, Istio, ArgoCD, Ingress-Nginx

**集群2**：
- 1 Master + 2 Worker
- 双环境：gaamingblog-prod, gaamingblog-canary
- 组件：Harbor, Istio, Ingress-Nginx

**全局组件**：
- GitLab：代码仓库
- Jenkins：CI/CD
- Prometheus：监控
- Grafana：可视化
- MySQL：数据库
- MongoDB：数据库

### 11.3 下一步

1. 按照本指南逐步部署
2. 验证每个阶段的结果
3. 配置CI/CD流水线
4. 进行应用部署测试
5. 配置监控和告警
