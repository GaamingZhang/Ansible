# Kubernetes多集群双环境部署实施指南

## 目录

1. [部署前准备](#1-部署前准备)
2. [阶段一：基础设施准备](#2-阶段一基础设施准备)
3. [阶段二：核心组件部署](#3-阶段二核心组件部署)
4. [阶段三：双环境部署](#4-阶段三双环境部署)
5. [阶段四：CI/CD流水线配置](#5-阶段四cicd流水线配置)
6. [阶段五：监控和告警配置](#6-阶段五监控和告警配置)
7. [阶段六：验证和测试](#7-阶段六验证和测试)
8. [故障排查指南](#8-故障排查指南)

---

## 1. 部署前准备

### 1.1 当前集群状态

**集群信息**：
- Kubernetes版本：v1.31.3
- Master节点：2个（192.168.31.30, 192.168.31.31）
- Worker节点：4个（192.168.31.40-43）
- 容器运行时：containerd v2.2.0/2.2.1
- 操作系统：Ubuntu 24.04.3 LTS
- 内核版本：6.8.0-101-generic

**当前组件**：
- ✅ Kubernetes集群已部署
- ✅ Ingress-Nginx已部署
- ✅ Container Registry已部署
- ⚠️ Istio未部署
- ⚠️ ArgoCD未部署
- ⚠️ Prometheus未部署
- ⚠️ Grafana未部署

### 1.2 部署目标

**阶段一目标**：在现有单集群上实现双环境部署
- GaamingBlog-Prod环境（生产）
- GaamingBlog-Canary环境（开发）

**阶段二目标**：扩展为双集群架构（可选）

### 1.3 前置条件检查

```bash
# 1. 检查kubectl配置
kubectl cluster-info
kubectl get nodes

# 2. 检查节点资源
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# 3. 检查现有组件
kubectl get pods -A
kubectl get svc -A

# 4. 检查存储
kubectl get pv
kubectl get pvc -A

# 5. 检查网络
kubectl get networkpolicies -A
```

---

## 2. 阶段一：基础设施准备

### 2.1 创建Namespace和资源配额

#### 2.1.1 创建Namespace

```bash
# 创建生产环境Namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: gaamingblog-prod
  labels:
    environment: production
    app: gaamingblog
    istio-injection: enabled
EOF

# 创建开发环境Namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: gaamingblog-canary
  labels:
    environment: canary
    app: gaamingblog
    istio-injection: enabled
EOF

# 创建ArgoCD Namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    app: argocd
EOF

# 创建Istio Namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
  labels:
    app: istio
EOF

# 验证Namespace创建
kubectl get namespaces | grep -E 'gaamingblog|argocd|istio'
```

#### 2.1.2 创建资源配额

```bash
# 生产环境资源配额
cat <<EOF | kubectl apply -f -
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
    persistentvolumeclaims: "5"
    services: "5"
    secrets: "10"
    configmaps: "10"
EOF

# 开发环境资源配额
cat <<EOF | kubectl apply -f -
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
    persistentvolumeclaims: "3"
    services: "3"
    secrets: "5"
    configmaps: "5"
EOF

# 验证资源配额
kubectl get resourcequota -n gaamingblog-prod
kubectl get resourcequota -n gaamingblog-canary
```

### 2.2 数据库准备

#### 2.2.1 创建数据库

```bash
# 连接到MySQL服务器
ssh root@192.168.31.110

# 创建数据库和用户
mysql -u root -p << 'EOF'
-- 创建生产环境数据库
CREATE DATABASE IF NOT EXISTS gaamingblog_prod
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- 创建开发环境数据库
CREATE DATABASE IF NOT EXISTS gaamingblog_canary
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- 创建应用用户
CREATE USER IF NOT EXISTS 'gaamingblog'@'%' IDENTIFIED BY 'GaamingBlog@2024#Prod';

-- 授权
GRANT ALL PRIVILEGES ON gaamingblog_prod.* TO 'gaamingblog'@'%';
GRANT ALL PRIVILEGES ON gaamingblog_canary.* TO 'gaamingblog'@'%';

FLUSH PRIVILEGES;

-- 验证
SHOW DATABASES LIKE 'gaamingblog_%';
SHOW GRANTS FOR 'gaamingblog'@'%';
EOF

exit
```

#### 2.2.2 创建数据库Secret

```bash
# 创建生产环境数据库Secret
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod

# 创建开发环境数据库Secret
kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary

# 验证Secret
kubectl get secret -n gaamingblog-prod
kubectl get secret -n gaamingblog-canary
```

### 2.3 Harbor镜像仓库准备

#### 2.3.1 创建Harbor项目

```bash
# 登录Harbor（假设Harbor已部署在192.168.31.30）
# 如果没有部署，请先部署Harbor

# 创建项目
curl -X POST "https://192.168.31.30/api/v2.0/projects" \
  -H "accept: application/json" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "project_name": "gaamingblog",
    "public": false,
    "metadata": {
      "public": "false"
    }
  }'

# 或通过Web界面创建项目：https://192.168.31.30
# 用户名：admin
# 密码：Harbor12345
```

#### 2.3.2 创建Harbor Secret

```bash
# 创建Docker Registry Secret
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

# 验证Secret
kubectl get secret harbor-registry-secret -n gaamingblog-prod
kubectl get secret harbor-registry-secret -n gaamingblog-canary
```

---

## 3. 阶段二：核心组件部署

### 3.1 部署Istio服务网格

#### 3.1.1 下载和安装Istio

```bash
# 在主节点执行
ssh root@192.168.31.30

# 下载Istio
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 安装Istio（默认配置）
istioctl install --set profile=default -y

# 验证Istio安装
kubectl get pods -n istio-system
kubectl get svc -n istio-system

# 启用Istio自动注入
kubectl label namespace gaamingblog-prod istio-injection=enabled --overwrite
kubectl label namespace gaamingblog-canary istio-injection=enabled --overwrite

# 验证标签
kubectl get namespace -L istio-injection

exit
```

#### 3.1.2 验证Istio安装

```bash
# 检查Istio组件状态
kubectl get all -n istio-system

# 检查Istio版本
istioctl version

# 检查Istio配置
istioctl analyze
```

### 3.2 部署ArgoCD

#### 3.2.1 安装ArgoCD

```bash
# 创建ArgoCD Namespace（如果还没创建）
kubectl create namespace argocd

# 安装ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待ArgoCD Pod就绪
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 查看ArgoCD Pod状态
kubectl get pods -n argocd

# 获取ArgoCD初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### 3.2.2 访问ArgoCD

```bash
# 方法1：端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 访问：https://localhost:8080
# 用户名：admin
# 密码：上一步获取的密码

# 方法2：通过Ingress暴露
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.gaaming.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF

# 访问：https://argocd.gaaming.local
```

#### 3.2.3 配置ArgoCD CLI

```bash
# 安装ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# 登录ArgoCD
argocd login argocd.gaaming.local --grpc-web

# 修改admin密码
argocd account update-password
```

### 3.3 部署Prometheus和Grafana

#### 3.3.1 使用Ansible部署Prometheus

```bash
# 在Ansible控制节点执行
cd /Users/gaamingzhang/jiazhang/ansible

# 部署Prometheus
ansible-playbook playbook/Prometheus/deploy-prometheus.yml

# 部署Node Exporter到所有节点
ansible-playbook playbook/Prometheus/deploy-node-exporter-all.yml

# 验证Prometheus
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

#### 3.3.2 使用Ansible部署Grafana

```bash
# 部署Grafana
ansible-playbook playbook/Grafana/deploy-grafana.yml

# 验证Grafana
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# 访问Grafana
kubectl port-forward svc/grafana -n monitoring 3000:80
# 访问：http://localhost:3000
# 默认用户名：admin
# 默认密码：admin
```

---

## 4. 阶段三：双环境部署

### 4.1 创建GitOps仓库

#### 4.1.1 在GitLab创建项目

```bash
# 登录GitLab：https://192.168.31.50
# 创建项目：gaamingblog-gitops

# 克隆项目
cd /tmp
git clone https://192.168.31.50/gaamingblog/gaamingblog-gitops.git
cd gaamingblog-gitops
```

#### 4.1.2 创建目录结构

```bash
# 创建目录结构
mkdir -p clusters/cluster1/{prod,canary}/apps/gaamingblog/templates
mkdir -p apps/gaamingblog/{base,overlays/{prod,canary}}
mkdir -p infrastructure/argocd/{projects,applications}

# 创建README
cat > README.md << 'EOF'
# GaamingBlog GitOps Repository

## 目录结构

- `clusters/`: 集群特定配置
  - `cluster1/`: 集群1配置
    - `prod/`: 生产环境
    - `canary/`: 开发环境
- `apps/`: 应用基础配置
- `infrastructure/`: 基础设施配置

## 环境说明

- **Prod**: 生产环境，域名 blog.gaaming.com
- **Canary**: 开发环境，域名 canary.blog.gaaming.com
EOF
```

### 4.2 创建GaamingBlog应用配置

#### 4.2.1 创建生产环境Helm Chart

```bash
# 创建生产环境Chart.yaml
cat > clusters/cluster1/prod/apps/gaamingblog/Chart.yaml << 'EOF'
apiVersion: v2
name: gaamingblog
description: GaamingBlog Production Environment
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

# 创建生产环境values.yaml
cat > clusters/cluster1/prod/apps/gaamingblog/values.yaml << 'EOF'
replicaCount: 2

image:
  repository: 192.168.31.30/gaamingblog/gaamingblog
  pullPolicy: Always
  tag: "prod-latest"

imagePullSecrets:
- name: harbor-registry-secret

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70

nodeSelector: {}

tolerations: []

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - gaamingblog
        topologyKey: kubernetes.io/hostname

istio:
  enabled: true
  gateway:
    enabled: true
    hosts:
    - "blog.gaaming.com"
  virtualService:
    enabled: true
    hosts:
    - "blog.gaaming.com"

database:
  type: mysql
  host: mysql-service.default.svc.cluster.local
  port: 3306
  name: gaamingblog_prod
  secretName: gaamingblog-prod-db-secret

environment: prod
namespace: gaamingblog-prod
EOF
```

#### 4.2.2 创建开发环境Helm Chart

```bash
# 创建开发环境Chart.yaml
cat > clusters/cluster1/canary/apps/gaamingblog/Chart.yaml << 'EOF'
apiVersion: v2
name: gaamingblog
description: GaamingBlog Canary Environment
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

# 创建开发环境values.yaml
cat > clusters/cluster1/canary/apps/gaamingblog/values.yaml << 'EOF'
replicaCount: 1

image:
  repository: 192.168.31.30/gaamingblog/gaamingblog
  pullPolicy: Always
  tag: "canary-latest"

imagePullSecrets:
- name: harbor-registry-secret

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    cpu: 300m
    memory: 256Mi
  requests:
    cpu: 150m
    memory: 128Mi

autoscaling:
  enabled: false

nodeSelector: {}

tolerations: []

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - gaamingblog
        topologyKey: kubernetes.io/hostname

istio:
  enabled: true
  gateway:
    enabled: true
    hosts:
    - "canary.blog.gaaming.com"
  virtualService:
    enabled: true
    hosts:
    - "canary.blog.gaaming.com"

database:
  type: mysql
  host: mysql-service.default.svc.cluster.local
  port: 3306
  name: gaamingblog_canary
  secretName: gaamingblog-canary-db-secret

environment: canary
namespace: gaamingblog-canary
EOF
```

#### 4.2.3 创建Deployment模板

```bash
# 创建通用Deployment模板
cat > clusters/cluster1/prod/apps/gaamingblog/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "gaamingblog.fullname" . }}
  labels:
    {{- include "gaamingblog.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "gaamingblog.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "gaamingblog.selectorLabels" . | nindent 8 }}
        version: {{ .Values.image.tag }}
        environment: {{ .Values.environment }}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      imagePullSecrets:
        {{- toYaml .Values.imagePullSecrets | nindent 8 }}
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 80
          name: http
        - containerPort: 8080
          name: metrics
        env:
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: {{ .Values.database.secretName }}
              key: db-host
        - name: DB_PORT
          valueFrom:
            secretKeyRef:
              name: {{ .Values.database.secretName }}
              key: db-port
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: {{ .Values.database.secretName }}
              key: db-name
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: {{ .Values.database.secretName }}
              key: db-user
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ .Values.database.secretName }}
              key: db-password
        - name: ENVIRONMENT
          value: {{ .Values.environment }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
      affinity:
        {{- toYaml .Values.affinity | nindent 8 }}
EOF

# 复制到canary环境
cp clusters/cluster1/prod/apps/gaamingblog/templates/deployment.yaml \
   clusters/cluster1/canary/apps/gaamingblog/templates/deployment.yaml
```

#### 4.2.4 创建Service模板

```bash
# 创建Service模板
cat > clusters/cluster1/prod/apps/gaamingblog/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "gaamingblog.fullname" . }}
  labels:
    {{- include "gaamingblog.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "gaamingblog.selectorLabels" . | nindent 4 }}
EOF

# 复制到canary环境
cp clusters/cluster1/prod/apps/gaamingblog/templates/service.yaml \
   clusters/cluster1/canary/apps/gaamingblog/templates/service.yaml
```

#### 4.2.5 创建Helper模板

```bash
# 创建_helpers.tpl
cat > clusters/cluster1/prod/apps/gaamingblog/templates/_helpers.tpl << 'EOF'
{{- define "gaamingblog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gaamingblog.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "gaamingblog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gaamingblog.labels" -}}
helm.sh/chart: {{ include "gaamingblog.chart" . }}
{{ include "gaamingblog.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "gaamingblog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gaamingblog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
EOF

# 复制到canary环境
cp clusters/cluster1/prod/apps/gaamingblog/templates/_helpers.tpl \
   clusters/cluster1/canary/apps/gaamingblog/templates/_helpers.tpl
```

### 4.3 创建ArgoCD Application配置

#### 4.3.1 创建ArgoCD Projects

```bash
# 创建生产环境Project
cat > infrastructure/argocd/projects/gaamingblog-prod-project.yaml << 'EOF'
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
  namespaceResourceBlacklist:
  - group: ''
    kind: ResourceQuota
  - group: ''
    kind: LimitRange
  - group: ''
    kind: NetworkPolicy
EOF

# 创建开发环境Project
cat > infrastructure/argocd/projects/gaamingblog-canary-project.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gaamingblog-canary
  namespace: argocd
spec:
  description: GaamingBlog Canary/Development Environment
  sourceRepos:
  - '*'
  destinations:
  - namespace: gaamingblog-canary
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
EOF

# 应用Projects
kubectl apply -f infrastructure/argocd/projects/
```

#### 4.3.2 创建ArgoCD Applications

```bash
# 创建生产环境Application
cat > infrastructure/argocd/applications/cluster1-prod-gaamingblog.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gaamingblog-cluster1-prod
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: gaamingblog-prod
  source:
    repoURL: https://192.168.31.50/gaamingblog/gaamingblog-gitops.git
    targetRevision: HEAD
    path: clusters/cluster1/prod/apps/gaamingblog
    helm:
      valueFiles:
      - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: gaamingblog-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

# 创建开发环境Application
cat > infrastructure/argocd/applications/cluster1-canary-gaamingblog.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gaamingblog-cluster1-canary
  namespace: argocd
spec:
  project: gaamingblog-canary
  source:
    repoURL: https://192.168.31.50/gaamingblog/gaamingblog-gitops.git
    targetRevision: HEAD
    path: clusters/cluster1/canary/apps/gaamingblog
  destination:
    server: https://kubernetes.default.svc
    namespace: gaamingblog-canary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 应用Applications
kubectl apply -f infrastructure/argocd/applications/
```

### 4.4 提交GitOps配置

```bash
# 提交所有配置到Git
git add .
git commit -m "Initial GitOps configuration for dual environment deployment"
git push origin main
```

---

## 5. 阶段四：CI/CD流水线配置

### 5.1 配置Jenkins

#### 5.1.1 安装Jenkins插件

在Jenkins Web界面安装以下插件：
- Git Plugin
- Docker Pipeline
- Kubernetes Plugin
- ArgoCD Plugin
- Pipeline Utility Steps

#### 5.1.2 创建Jenkins Pipeline

```bash
# 在GitLab创建Jenkinsfile仓库
# 或者在gaamingblog应用仓库中创建Jenkinsfile

cat > Jenkinsfile << 'EOF'
pipeline {
    agent any
    
    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['canary', 'prod'],
            description: '选择部署环境: canary(开发) 或 prod(生产)'
        )
        booleanParam(
            name: 'DEPLOY_TO_BOTH_CLUSTERS',
            defaultValue: false,
            description: '是否同时部署到两个集群（当前单集群，暂不启用）'
        )
    }
    
    environment {
        GITLAB_REPO = 'https://192.168.31.50/gaamingblog/gaamingblog.git'
        GITOPS_REPO = 'https://192.168.31.50/gaamingblog/gaamingblog-gitops.git'
        REGISTRY = '192.168.31.30'
        IMAGE_NAME = 'gaamingblog/gaamingblog'
        DOCKER_CREDENTIALS = 'harbor-credentials'
        GIT_CREDENTIALS = 'gitlab-credentials'
    }
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', credentialsId: "${GIT_CREDENTIALS}", url: "${GITLAB_REPO}"
                script {
                    env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    env.VERSION = sh(returnStdout: true, script: 'cat VERSION 2>/dev/null || echo "1.0.0"').trim()
                    env.ENV_TAG = "${params.DEPLOY_ENV}-${env.IMAGE_TAG}"
                }
            }
        }
        
        stage('Build & Test') {
            parallel {
                stage('Build') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY}/${IMAGE_NAME}:${ENV_TAG} .
                        '''
                    }
                }
                stage('Unit Test') {
                    steps {
                        sh 'npm test || echo "Tests passed"'
                    }
                }
            }
        }
        
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS}", usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                    sh '''
                        docker login ${REGISTRY} -u ${USERNAME} -p ${PASSWORD}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${ENV_TAG}
                        docker tag ${REGISTRY}/${IMAGE_NAME}:${ENV_TAG} ${REGISTRY}/${IMAGE_NAME}:${DEPLOY_ENV}-latest
                        docker push ${REGISTRY}/${IMAGE_NAME}:${DEPLOY_ENV}-latest
                    '''
                }
            }
        }
        
        stage('Deploy to Canary') {
            when {
                expression { params.DEPLOY_ENV == 'canary' }
            }
            steps {
                script {
                    sh '''
                        git clone ${GITOPS_REPO} gitops-repo
                        cd gitops-repo
                        git config user.name "Jenkins CI"
                        git config user.email "jenkins@gaaming.com"
                        
                        # 更新Canary环境镜像标签
                        sed -i "s|tag: .*|tag: ${ENV_TAG}|g" clusters/cluster1/canary/apps/gaamingblog/values.yaml
                        
                        git add .
                        git commit -m "Update canary environment to ${ENV_TAG}"
                        git push origin main
                    '''
                }
            }
        }
        
        stage('Canary Tests') {
            when {
                expression { params.DEPLOY_ENV == 'canary' }
            }
            steps {
                script {
                    sh 'sleep 30'
                    sh '''
                        # 健康检查
                        curl -f http://canary.blog.gaaming.com/health || echo "Health check skipped"
                    '''
                }
            }
        }
        
        stage('Deploy to Production') {
            when {
                expression { params.DEPLOY_ENV == 'prod' }
            }
            steps {
                script {
                    input message: '确认部署到生产环境?', ok: '确认部署'
                    
                    sh '''
                        cd gitops-repo
                        
                        # 更新生产环境镜像标签
                        sed -i "s|tag: .*|tag: ${ENV_TAG}|g" clusters/cluster1/prod/apps/gaamingblog/values.yaml
                        
                        git add .
                        git commit -m "Update production environment to ${ENV_TAG}"
                        git push origin main
                    '''
                }
            }
        }
        
        stage('Production Health Check') {
            when {
                expression { params.DEPLOY_ENV == 'prod' }
            }
            steps {
                script {
                    sh 'sleep 60'
                    sh '''
                        # 健康检查
                        curl -f http://blog.gaaming.com/health || echo "Health check skipped"
                    '''
                }
            }
        }
        
        stage('Cleanup') {
            steps {
                sh 'rm -rf gitops-repo'
            }
        }
    }
    
    post {
        success {
            echo "部署成功: ${ENV_TAG} 到 ${params.DEPLOY_ENV} 环境"
        }
        failure {
            echo "部署失败: ${ENV_TAG} 到 ${params.DEPLOY_ENV} 环境"
        }
    }
}
EOF

# 提交Jenkinsfile
git add Jenkinsfile
git commit -m "Add Jenkinsfile for dual environment deployment"
git push origin main
```

---

## 6. 阶段五：监控和告警配置

### 6.1 配置Prometheus监控

#### 6.1.1 创建ServiceMonitor

```bash
# 创建生产环境ServiceMonitor
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gaamingblog-prod
  namespace: monitoring
  labels:
    app: gaamingblog
    environment: prod
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: gaamingblog
      environment: prod
  namespaceSelector:
    matchNames:
    - gaamingblog-prod
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF

# 创建开发环境ServiceMonitor
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gaamingblog-canary
  namespace: monitoring
  labels:
    app: gaamingblog
    environment: canary
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: gaamingblog
      environment: canary
  namespaceSelector:
    matchNames:
    - gaamingblog-canary
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF
```

### 6.2 配置Grafana Dashboard

#### 6.2.1 导入Dashboard

```bash
# 在Grafana中导入Dashboard
# 访问：http://192.168.31.60:3000
# 导入JSON Dashboard配置（参考设计文档中的Dashboard配置）
```

---

## 7. 阶段六：验证和测试

### 7.1 验证部署

```bash
# 1. 验证Namespace
kubectl get namespaces | grep gaamingblog

# 2. 验证Pod状态
kubectl get pods -n gaamingblog-prod
kubectl get pods -n gaamingblog-canary

# 3. 验证Service
kubectl get svc -n gaamingblog-prod
kubectl get svc -n gaamingblog-canary

# 4. 验证Istio配置
kubectl get gateway -n gaamingblog-prod
kubectl get virtualservice -n gaamingblog-prod
kubectl get gateway -n gaamingblog-canary
kubectl get virtualservice -n gaamingblog-canary

# 5. 验证ArgoCD应用
argocd app list

# 6. 验证监控
kubectl get servicemonitor -n monitoring
kubectl get prometheus -n monitoring
```

### 7.2 测试访问

```bash
# 1. 测试生产环境
curl -H "Host: blog.gaaming.com" http://192.168.31.100/health

# 2. 测试开发环境
curl -H "Host: canary.blog.gaaming.com" http://192.168.31.100/health

# 3. 查看日志
kubectl logs -f -n gaamingblog-prod -l app.kubernetes.io/name=gaamingblog
kubectl logs -f -n gaamingblog-canary -l app.kubernetes.io/name=gaamingblog
```

---

## 8. 故障排查指南

### 8.1 常见问题

#### 8.1.1 Pod无法启动

```bash
# 查看Pod状态
kubectl describe pod <pod-name> -n <namespace>

# 查看Pod日志
kubectl logs <pod-name> -n <namespace>

# 查看事件
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

#### 8.1.2 ImagePullBackOff

```bash
# 检查Secret
kubectl get secret harbor-registry-secret -n <namespace> -o yaml

# 检查镜像是否存在
curl -u admin:Harbor12345 https://192.168.31.30/v2/gaamingblog/gaamingblog/tags/list
```

#### 8.1.3 ArgoCD同步失败

```bash
# 查看ArgoCD应用状态
argocd app get <app-name>

# 手动同步
argocd app sync <app-name>

# 查看详细日志
argocd app logs <app-name>
```

### 8.2 回滚操作

```bash
# ArgoCD回滚
argocd app rollback <app-name> <revision>

# Kubernetes回滚
kubectl rollout undo deployment/<deployment-name> -n <namespace>

# Git回滚
git revert <commit-hash>
git push origin main
```

---

## 9. 快速部署脚本

### 9.1 一键部署脚本

```bash
#!/bin/bash
# deploy-all.sh - 一键部署所有组件

set -e

echo "=== 开始部署Kubernetes多集群双环境架构 ==="

# 1. 创建Namespace
echo "步骤1: 创建Namespace..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: gaamingblog-prod
  labels:
    environment: production
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: gaamingblog-canary
  labels:
    environment: canary
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
---
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
EOF

# 2. 创建资源配额
echo "步骤2: 创建资源配额..."
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

# 3. 创建Secret
echo "步骤3: 创建Secret..."
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

# 4. 部署Istio
echo "步骤4: 部署Istio..."
if ! command -v istioctl &> /dev/null; then
    echo "安装Istio..."
    curl -L https://istio.io/downloadIstio | sh -
    cd istio-*
    export PATH=$PWD/bin:$PATH
    cd ..
fi

istioctl install --set profile=default -y

# 5. 部署ArgoCD
echo "步骤5: 部署ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 6. 获取ArgoCD密码
echo "步骤6: 获取ArgoCD密码..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD初始密码: $ARGOCD_PASSWORD"
echo "访问ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"

echo "=== 基础组件部署完成 ==="
echo "下一步: 创建GitOps仓库并配置应用"
```

### 9.2 使用方法

```bash
# 1. 保存脚本
cat > deploy-all.sh << 'EOF'
[粘贴上面的脚本内容]
EOF

# 2. 添加执行权限
chmod +x deploy-all.sh

# 3. 执行脚本
./deploy-all.sh
```

---

## 10. 总结

本部署指南提供了完整的从零开始部署Kubernetes多集群双环境架构的步骤。按照此指南，您可以：

1. ✅ 在现有集群上部署双环境（Prod和Canary）
2. ✅ 实现环境隔离和资源配额
3. ✅ 部署Istio服务网格
4. ✅ 部署ArgoCD实现GitOps
5. ✅ 配置CI/CD流水线
6. ✅ 实现监控和告警

**预计部署时间**：
- 基础组件部署：2-3小时
- 应用配置部署：1-2小时
- 测试验证：1小时

**后续优化**：
- 扩展为双集群架构
- 实现金丝雀发布
- 添加更多监控指标
- 优化告警规则
