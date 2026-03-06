# 多集群从零部署快速命令清单

## 快速部署命令（按顺序执行）

### 0. 前置准备

```bash
# 进入Ansible目录
cd /Users/gaamingzhang/jiazhang/ansible

# 检查Ansible配置
ansible --version
ansible all -m ping
```

### 1. 备份现有数据

```bash
# 备份kubeconfig
cp -r ~/.kube ~/.kube.backup.$(date +%Y%m%d)

# 备份重要资源
kubectl get configmap -A -o yaml > /tmp/configmaps-backup.yaml
kubectl get secret -A -o yaml > /tmp/secrets-backup.yaml
kubectl get pv -o yaml > /tmp/pv-backup.yaml
kubectl get pvc -A -o yaml > /tmp/pvc-backup.yaml

# 打包备份
tar -czf k8s-backup-$(date +%Y%m%d).tar.gz /tmp/*backup* ~/.kube.backup.*
```

### 2. 清理现有集群

```bash
# 清理所有节点
for ip in 192.168.31.30 192.168.31.31 192.168.31.40 192.168.31.41 192.168.31.42 192.168.31.43; do
  echo "Cleaning $ip..."
  ssh root@$ip << 'EOF'
    kubeadm reset -f || true
    rm -rf /etc/kubernetes/
    rm -rf /var/lib/kubelet/
    rm -rf /var/lib/dockershim/
    rm -rf /var/lib/etcd/
    rm -rf /var/lib/cni/
    rm -rf /etc/cni/
    rm -rf /root/.kube/config
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
    systemctl restart containerd
EOF
done

# 验证清理
for ip in 192.168.31.30 192.168.31.31 192.168.31.40 192.168.31.41 192.168.31.42 192.168.31.43; do
  echo "=== $ip ==="
  ssh root@$ip 'systemctl status kubelet 2>&1 | head -3 || echo "kubelet not running"'
done
```

### 3. 更新Inventory配置

```bash
# 创建新的inventory配置
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

# 创建集群变量文件
cat > group_vars/cluster1.yml << 'EOF'
kubernetes_cluster_name: "cluster1"
kubernetes_version: "1.31.3"
kubernetes_pod_network_cidr: "10.244.1.0/16"
kubernetes_service_cidr: "10.96.1.0/12"
kube_vip_vip: "192.168.31.100"
kube_vip_interface: "ens33"
containerd_version: "1.7.22"
cni_type: "calico"
calico_version: "3.29.1"
EOF

cat > group_vars/cluster2.yml << 'EOF'
kubernetes_cluster_name: "cluster2"
kubernetes_version: "1.31.3"
kubernetes_pod_network_cidr: "10.244.2.0/16"
kubernetes_service_cidr: "10.96.2.0/12"
kube_vip_vip: "192.168.31.101"
kube_vip_interface: "ens33"
containerd_version: "1.7.22"
cni_type: "calico"
calico_version: "3.29.1"
EOF
```

### 4. 部署集群1

```bash
# 系统准备
ansible-playbook playbook/kubernetes/01-system-prepare.yml -l cluster1

# 安装containerd
ansible-playbook playbook/kubernetes/02-install-containerd.yml -l cluster1

# 安装Kubernetes组件
ansible-playbook playbook/kubernetes/03-install-kubernetes.yml -l cluster1

# 安装kube-vip
ansible-playbook playbook/kubernetes/04-install-kube-vip.yml -l cluster1_first_master

# 初始化Master
ansible-playbook playbook/kubernetes/05-init-kubernetes-master.yml -l cluster1_first_master

# Worker加入集群
ansible-playbook playbook/kubernetes/07-join-kubernetes-worker.yml -l cluster1_workers

# 安装CNI
ansible-playbook playbook/kubernetes/08-install-cni.yml -l cluster1_first_master

# 验证集群
ansible-playbook playbook/kubernetes/09-verify-cluster.yml -l cluster1_first_master

# 获取kubeconfig
ssh root@192.168.31.30 'cat /etc/kubernetes/admin.conf' > ~/.kube/config.cluster1
export KUBECONFIG=~/.kube/config.cluster1
kubectl config rename-context kubernetes-admin@kubernetes cluster1
kubectl get nodes
```

### 5. 部署集群2

```bash
# 系统准备
ansible-playbook playbook/kubernetes/01-system-prepare.yml -l cluster2

# 安装containerd
ansible-playbook playbook/kubernetes/02-install-containerd.yml -l cluster2

# 安装Kubernetes组件
ansible-playbook playbook/kubernetes/03-install-kubernetes.yml -l cluster2

# 安装kube-vip
ansible-playbook playbook/kubernetes/04-install-kube-vip.yml -l cluster2_first_master

# 初始化Master
ansible-playbook playbook/kubernetes/05-init-kubernetes-master.yml -l cluster2_first_master

# Worker加入集群
ansible-playbook playbook/kubernetes/07-join-kubernetes-worker.yml -l cluster2_workers

# 安装CNI
ansible-playbook playbook/kubernetes/08-install-cni.yml -l cluster2_first_master

# 验证集群
ansible-playbook playbook/kubernetes/09-verify-cluster.yml -l cluster2_first_master

# 获取kubeconfig
ssh root@192.168.31.31 'cat /etc/kubernetes/admin.conf' > ~/.kube/config.cluster2
export KUBECONFIG=~/.kube/config.cluster2
kubectl config rename-context kubernetes-admin@kubernetes cluster2
kubectl get nodes
```

### 6. 配置多集群访问

```bash
# 合并kubeconfig
export KUBECONFIG=~/.kube/config.cluster1:~/.kube/config.cluster2
kubectl config view --flatten > ~/.kube/config

# 验证上下文
kubectl config get-contexts

# 切换集群
kubectl config use-context cluster1
kubectl get nodes

kubectl config use-context cluster2
kubectl get nodes
```

### 7. 部署Harbor（集群1和集群2）

```bash
# 安装Helm（如果还没安装）
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 添加Harbor仓库
helm repo add harbor https://helm.goharbor.io
helm repo update

# 集群1部署Harbor
kubectl config use-context cluster1
kubectl create namespace harbor

helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.nodePort.ports.https.nodePort=30003 \
  --set externalURL=https://192.168.31.30:30003 \
  --set harborAdminPassword="Harbor12345" \
  --set persistence.persistentVolumeClaim.registry.size=50Gi

# 等待就绪
kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=600s

# 集群2部署Harbor
kubectl config use-context cluster2
kubectl create namespace harbor

helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.nodePort.ports.https.nodePort=30003 \
  --set externalURL=https://192.168.31.31:30003 \
  --set harborAdminPassword="Harbor12345" \
  --set persistence.persistentVolumeClaim.registry.size=50Gi

kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=600s
```

### 8. 部署Istio（集群1和集群2）

```bash
# 下载Istio
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 集群1部署Istio
kubectl config use-context cluster1

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
EOF

istioctl install -f istio-cluster1.yaml -y
kubectl get pods -n istio-system

# 集群2部署Istio
kubectl config use-context cluster2

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
EOF

istioctl install -f istio-cluster2.yaml -y
kubectl get pods -n istio-system
```

### 9. 部署ArgoCD（集群1）

```bash
# 切换到集群1
kubectl config use-context cluster1

# 创建Namespace
kubectl create namespace argocd

# 部署ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待就绪
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 获取初始密码
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD密码: $ARGOCD_PASSWORD"

# 端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &

# 访问：https://192.168.31.30:8080
# 用户名：admin
# 密码：上面获取的密码
```

### 10. 部署Ingress-Nginx（集群1和集群2）

```bash
# 集群1
kubectl config use-context cluster1
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# 集群2
kubectl config use-context cluster2
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

### 11. 创建双环境Namespace和Secret

```bash
# 集群1 - 创建Namespace
kubectl config use-context cluster1
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

# 集群1 - 创建Secret
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod

kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary

# 集群2 - 重复相同操作
kubectl config use-context cluster2
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod

kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.31:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.31:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary
```

### 12. 部署Prometheus和Grafana

```bash
# 使用Ansible部署
ansible-playbook playbook/Prometheus/deploy-prometheus.yml -l cluster1_first_master
ansible-playbook playbook/Prometheus/deploy-node-exporter-all.yml -l cluster1

ansible-playbook playbook/Prometheus/deploy-prometheus.yml -l cluster2_first_master
ansible-playbook playbook/Prometheus/deploy-node-exporter-all.yml -l cluster2

ansible-playbook playbook/Grafana/deploy-grafana.yml
```

### 13. 验证部署

```bash
# 验证集群1
kubectl config use-context cluster1
echo "=== 集群1节点 ==="
kubectl get nodes
echo "=== 集群1 Pod ==="
kubectl get pods -A
echo "=== 集群1 Service ==="
kubectl get svc -A

# 验证集群2
kubectl config use-context cluster2
echo "=== 集群2节点 ==="
kubectl get nodes
echo "=== 集群2 Pod ==="
kubectl get pods -A
echo "=== 集群2 Service ==="
kubectl get svc -A
```

### 14. 访问地址

```bash
# Harbor集群1
echo "Harbor集群1: https://192.168.31.30:30003"
echo "用户名: admin"
echo "密码: Harbor12345"

# Harbor集群2
echo "Harbor集群2: https://192.168.31.31:30003"

# ArgoCD
echo "ArgoCD: https://192.168.31.30:8080"
echo "用户名: admin"
echo "密码: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

# Grafana
kubectl port-forward svc/grafana -n monitoring 3000:80 --address 0.0.0.0 &
echo "Grafana: http://192.168.31.60:3000"
echo "用户名: admin"
echo "密码: admin"

# Prometheus
kubectl port-forward svc/prometheus -n monitoring 9090:9090 --address 0.0.0.0 &
echo "Prometheus: http://192.168.31.80:9090"
```

## 一键部署脚本

```bash
#!/bin/bash
# deploy-multicluster.sh

set -e

echo "=== 开始部署Kubernetes多集群双环境架构 ==="

# 执行步骤1-14
# 可以将上面的命令按顺序放入这个脚本中

echo "=== 部署完成 ==="
echo "集群1 API: https://192.168.31.100:6443"
echo "集群2 API: https://192.168.31.101:6443"
```

## 预计时间

- **清理现有集群**：30分钟
- **部署集群1**：1小时
- **部署集群2**：1小时
- **基础设施组件**：2小时
- **双环境配置**：1小时
- **监控部署**：1小时
- **验证测试**：30分钟
- **总计**：约7小时

## 下一步

1. 创建GitOps仓库
2. 配置ArgoCD Applications
3. 部署GaamingBlog应用
4. 配置CI/CD流水线
5. 测试双环境访问

详细步骤请参考：[multicluster-deployment-from-scratch.md](./multicluster-deployment-from-scratch.md)
