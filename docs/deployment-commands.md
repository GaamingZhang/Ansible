# Kubernetes多集群双环境部署命令清单

## 快速部署命令（按顺序执行）

### 1. 前置检查

```bash
# 检查集群状态
kubectl cluster-info
kubectl get nodes
kubectl get namespaces

# 检查资源
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### 2. 创建Namespace和资源配额

```bash
# 创建Namespace
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary
kubectl create namespace argocd
kubectl create namespace istio-system

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

### 3. 创建Secret

```bash
# 创建数据库Secret
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

# 创建Harbor Registry Secret
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary
```

### 4. 准备数据库

```bash
# SSH到MySQL服务器
ssh root@192.168.31.110

# 创建数据库
mysql -u root -p << 'EOF'
CREATE DATABASE IF NOT EXISTS gaamingblog_prod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS gaamingblog_canary CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'gaamingblog'@'%' IDENTIFIED BY 'GaamingBlog@2024#Prod';
GRANT ALL PRIVILEGES ON gaamingblog_prod.* TO 'gaamingblog'@'%';
GRANT ALL PRIVILEGES ON gaamingblog_canary.* TO 'gaamingblog'@'%';
FLUSH PRIVILEGES;
SHOW DATABASES LIKE 'gaamingblog_%';
EOF

exit
```

### 5. 部署Istio

```bash
# 下载Istio（在主节点执行）
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 安装Istio
istioctl install --set profile=default -y

# 验证
kubectl get pods -n istio-system
istioctl version
```

### 6. 部署ArgoCD

```bash
# 安装ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待就绪
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 端口转发访问
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 访问：https://localhost:8080
# 用户名：admin
# 密码：上一步获取的密码
```

### 7. 部署Prometheus和Grafana（使用Ansible）

```bash
# 在Ansible控制节点执行
cd /Users/gaamingzhang/jiazhang/ansible

# 部署Prometheus
ansible-playbook playbook/Prometheus/deploy-prometheus.yml

# 部署Node Exporter
ansible-playbook playbook/Prometheus/deploy-node-exporter-all.yml

# 部署Grafana
ansible-playbook playbook/Grafana/deploy-grafana.yml

# 验证
kubectl get pods -n monitoring
```

### 8. 创建GitOps仓库

```bash
# 在GitLab创建项目：gaamingblog-gitops
# 然后克隆到本地

cd /tmp
git clone https://192.168.31.50/gaamingblog/gaamingblog-gitops.git
cd gaamingblog-gitops

# 创建目录结构
mkdir -p clusters/cluster1/{prod,canary}/apps/gaamingblog/templates
mkdir -p infrastructure/argocd/{projects,applications}

# 创建README
cat > README.md << 'EOF'
# GaamingBlog GitOps Repository

## 环境
- **Prod**: 生产环境，域名 blog.gaaming.com
- **Canary**: 开发环境，域名 canary.blog.gaaming.com
EOF

# 提交
git add .
git commit -m "Initial GitOps repository"
git push origin main
```

### 9. 创建ArgoCD Projects和Applications

```bash
# 创建Projects
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gaamingblog-prod
  namespace: argocd
spec:
  description: GaamingBlog Production Environment
  sourceRepos:
  - '*'
  destinations:
  - namespace: gaamingblog-prod
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gaamingblog-canary
  namespace: argocd
spec:
  description: GaamingBlog Canary Environment
  sourceRepos:
  - '*'
  destinations:
  - namespace: gaamingblog-canary
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
EOF

# 创建Applications（需要先在GitOps仓库中创建应用配置）
# 参考详细部署指南中的配置文件
```

### 10. 验证部署

```bash
# 检查Namespace
kubectl get namespaces | grep gaamingblog

# 检查Pod
kubectl get pods -n gaamingblog-prod
kubectl get pods -n gaamingblog-canary

# 检查ArgoCD应用
argocd app list

# 检查Istio
kubectl get pods -n istio-system

# 检查监控
kubectl get pods -n monitoring
```

## 一键部署脚本

```bash
# 创建并执行一键部署脚本
cat > deploy-all.sh << 'EOF'
#!/bin/bash
set -e

echo "=== 开始部署 ==="

# 1. 创建Namespace
echo "创建Namespace..."
kubectl create namespace gaamingblog-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gaamingblog-canary --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled --overwrite
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled --overwrite

# 2. 创建Secret
echo "创建Secret..."
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary --dry-run=client -o yaml | kubectl apply -f -

# 3. 部署Istio
echo "部署Istio..."
if ! command -v istioctl &> /dev/null; then
    echo "请先安装Istio"
    exit 1
fi
istioctl install --set profile=default -y

# 4. 部署ArgoCD
echo "部署ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 5. 获取ArgoCD密码
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD密码: $ARGOCD_PASSWORD"

echo "=== 部署完成 ==="
EOF

chmod +x deploy-all.sh
./deploy-all.sh
```

## 访问地址

- **ArgoCD**: `kubectl port-forward svc/argocd-server -n argocd 8080:443` → https://localhost:8080
- **Grafana**: `kubectl port-forward svc/grafana -n monitoring 3000:80` → http://localhost:3000
- **Prometheus**: `kubectl port-forward svc/prometheus -n monitoring 9090:9090` → http://localhost:9090
- **生产环境**: http://blog.gaaming.com (需要配置DNS或hosts)
- **开发环境**: http://canary.blog.gaaming.com (需要配置DNS或hosts)

## 故障排查

```bash
# 查看Pod日志
kubectl logs -f -n <namespace> <pod-name>

# 查看Pod详情
kubectl describe pod <pod-name> -n <namespace>

# 查看事件
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# 查看ArgoCD应用状态
argocd app get <app-name>

# 手动同步ArgoCD应用
argocd app sync <app-name>
```

## 下一步

1. 在GitLab创建GitOps仓库
2. 创建应用Helm Chart配置
3. 配置ArgoCD Applications
4. 配置CI/CD流水线
5. 部署应用并验证

详细步骤请参考：[deployment-guide.md](./deployment-guide.md)
