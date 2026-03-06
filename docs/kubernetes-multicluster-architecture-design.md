# Kubernetes多集群架构设计方案

## 目录

1. [架构设计总览](#1-架构设计总览)
2. [节点角色分配和IP规划](#2-节点角色分配和ip规划)
3. [技术选型和部署方案](#3-技术选型和部署方案)
4. [网络架构设计](#4-网络架构设计)
5. [GitOps工作流设计](#5-gitops工作流设计)
6. [双环境部署架构设计](#6-双环境部署架构设计)
7. [CI/CD流水线设计](#7-cicd流水线设计)
8. [高可用性和容灾方案](#8-高可用性和容灾方案)
9. [多集群监控系统设计](#9-多集群监控系统设计)
10. [安全性考虑](#10-安全性考虑)
11. [实施步骤和最佳实践建议](#11-实施步骤和最佳实践建议)

---

## 1. 架构设计总览

### 1.1 整体架构图（Mermaid格式）

```mermaid
graph TB
    subgraph "外部访问层"
        DNS[DNS域名解析<br/>blog.gaaming.com]
        GLB[全局负载均衡器<br/>Nginx/HAProxy]
    end

    subgraph "CI/CD层"
        GitLab[GitLab代码仓库<br/>192.168.31.50]
        Jenkins[Jenkins CI/CD<br/>192.168.31.70]
        ArgoCD[ArgoCD GitOps<br/>集群1主节点]
    end

    subgraph "集群1"
        M1[Master节点<br/>192.168.31.30<br/>API Server, etcd<br/>镜像仓库, ArgoCD]
        W1[Worker节点1<br/>192.168.31.40<br/>GaamingBlog-Prod<br/>GaamingBlog-Canary]
        W2[Worker节点2<br/>192.168.31.41<br/>GaamingBlog-Prod<br/>GaamingBlog-Canary]
        Registry1[镜像仓库<br/>Harbor/Nexus<br/>registry.cluster1.local]
        
        subgraph "集群1服务网格"
            Istio1[Istio控制平面]
            Ingress1[Istio Ingress Gateway]
        end
    end

    subgraph "集群2"
        M2[Master节点<br/>192.168.31.31<br/>API Server, etcd<br/>镜像仓库]
        W3[Worker节点1<br/>192.168.31.42<br/>GaamingBlog-Prod<br/>GaamingBlog-Canary]
        W4[Worker节点2<br/>192.168.31.43<br/>GaamingBlog-Prod<br/>GaamingBlog-Canary]
        Registry2[镜像仓库<br/>Harbor/Nexus<br/>registry.cluster2.local]
        
        subgraph "集群2服务网格"
            Istio2[Istio控制平面]
            Ingress2[Istio Ingress Gateway]
        end
    end

    subgraph "监控与存储"
        Prometheus[Prometheus监控<br/>192.168.31.80]
        Grafana[Grafana可视化<br/>192.168.31.60]
        MySQL[MySQL数据库<br/>192.168.31.110]
        MongoDB[MongoDB数据库<br/>192.168.31.140]
    end

    DNS --> GLB
    GitLab --> Jenkins
    Jenkins --> Registry1
    Jenkins --> Registry2
    Jenkins --> GitLab
    GitLab --> ArgoCD
    ArgoCD --> M1
    ArgoCD -.->|多集群管理| M2
    
    GLB -->|负载均衡| Ingress1
    GLB -->|负载均衡| Ingress2
    
    M1 --> W1
    M1 --> W2
    M2 --> W3
    M2 --> W4
    
    W1 --> Istio1
    W2 --> Istio1
    W3 --> Istio2
    W4 --> Istio2
    
    M1 --> Registry1
    M2 --> Registry2
    
    Prometheus --> M1
    Prometheus --> M2
    Grafana --> Prometheus
```

### 1.2 数据流架构图

```mermaid
sequenceDiagram
    participant User as 用户
    participant DNS as DNS
    participant GLB as 全局负载均衡
    participant IG1 as 集群1 Ingress
    participant IG2 as 集群2 Ingress
    participant Istio1 as Istio集群1
    participant Istio2 as Istio集群2
    participant App1Prod as GaamingBlog-Prod集群1
    participant App1Canary as GaamingBlog-Canary集群1
    participant App2Prod as GaamingBlog-Prod集群2
    participant App2Canary as GaamingBlog-Canary集群2
    participant DB as 数据库

    User->>DNS: 解析 blog.gaaming.com (生产)
    DNS->>GLB: 返回GLB IP
    User->>GLB: HTTP请求
    GLB->>IG1: 转发请求(权重50%)
    GLB->>IG2: 转发请求(权重50%)
    IG1->>Istio1: 路由到Prod服务
    IG2->>Istio2: 路由到Prod服务
    Istio1->>App1Prod: 负载均衡到Pod
    Istio2->>App2Prod: 负载均衡到Pod
    App1Prod->>DB: 读写数据
    App2Prod->>DB: 读写数据
    
    Note over User,App2Canary: Canary环境访问流程
    User->>DNS: 解析 canary.blog.gaaming.com (开发)
    DNS->>GLB: 返回GLB IP
    User->>GLB: HTTP请求
    GLB->>IG1: 转发请求(权重50%)
    GLB->>IG2: 转发请求(权重50%)
    IG1->>Istio1: 路由到Canary服务
    IG2->>Istio2: 路由到Canary服务
    Istio1->>App1Canary: 负载均衡到Pod
    Istio2->>App2Canary: 负载均衡到Pod
    App1Canary->>DB: 读写数据
    App2Canary->>DB: 读写数据
```

---

## 2. 节点角色分配和IP规划

### 2.1 IP地址规划表

| 节点角色 | 主机名 | IP地址 | 集群 | 主要组件 |
|---------|--------|--------|------|---------|
| **集群1 Master** | cluster1-master | 192.168.31.30 | Cluster-1 | K8s Master, etcd, Harbor, ArgoCD, Istio控制平面 |
| **集群1 Worker1** | cluster1-worker1 | 192.168.31.40 | Cluster-1 | K8s Worker, GaamingBlog-Prod, GaamingBlog-Canary |
| **集群1 Worker2** | cluster1-worker2 | 192.168.31.41 | Cluster-1 | K8s Worker, GaamingBlog-Prod, GaamingBlog-Canary |
| **集群2 Master** | cluster2-master | 192.168.31.31 | Cluster-2 | K8s Master, etcd, Harbor, Istio控制平面 |
| **集群2 Worker1** | cluster2-worker1 | 192.168.31.42 | Cluster-2 | K8s Worker, GaamingBlog-Prod, GaamingBlog-Canary |
| **集群2 Worker2** | cluster2-worker2 | 192.168.31.43 | Cluster-2 | K8s Worker, GaamingBlog-Prod, GaamingBlog-Canary |
| **GitLab** | gitlab | 192.168.31.50 | - | GitLab CE |
| **Jenkins** | jenkins | 192.168.31.70 | - | Jenkins CI/CD |
| **Prometheus** | prometheus | 192.168.31.80 | - | Prometheus监控 |
| **Grafana** | grafana | 192.168.31.60 | - | Grafana可视化 |
| **MySQL** | mysql | 192.168.31.110 | - | MySQL数据库 |
| **MongoDB** | mongodb | 192.168.31.140 | - | MongoDB数据库 |

**环境部署说明**：
- **GaamingBlog-Prod（生产环境）**：两个集群都部署生产环境，通过域名 `blog.gaaming.com` 访问
- **GaamingBlog-Canary（开发环境）**：两个集群都部署开发环境，通过域名 `canary.blog.gaaming.com` 访问
- 每个集群的Worker节点同时运行两个环境的Pod，通过Namespace隔离
- 两个集群互为备份，提供高可用性

### 2.2 网络规划

| 网络类型 | CIDR | 用途 |
|---------|------|------|
| 节点网络 | 192.168.31.0/24 | 物理节点通信 |
| 集群1 Pod网络 | 10.244.1.0/16 | 集群1 Pod IP |
| 集群1 Service网络 | 10.96.1.0/12 | 集群1 Service IP |
| 集群2 Pod网络 | 10.244.2.0/16 | 集群2 Pod IP |
| 集群2 Service网络 | 10.96.2.0/12 | 集群2 Service IP |
| 集群1 VIP | 192.168.31.100 | 集群1 API Server VIP |
| 集群2 VIP | 192.168.31.101 | 集群2 API Server VIP |

### 2.3 更新后的Inventory配置

```ini
[allNodes:children]
cluster1
cluster2
gitlab_server
jenkins_server
prometheus_server
grafana_server
mysql_server
mongodb_server

# 集群1 - 生产环境
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

# 集群2 - 预发环境
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

# CI/CD 组件
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
```

---

## 3. 技术选型和部署方案

### 3.1 核心技术栈

| 组件类别 | 技术选型 | 版本 | 用途 |
|---------|---------|------|------|
| **容器编排** | Kubernetes | v1.31.3 | 容器编排平台 |
| **容器运行时** | containerd | v1.7.22 | 容器运行时 |
| **CNI网络** | Calico | v3.29.1 | Pod网络和网络策略 |
| **服务网格** | Istio | v1.21.0 | 服务发现、流量管理、可观测性 |
| **配置管理** | Helm | v3.14.0 | 包管理和配置编排 |
| **GitOps** | ArgoCD | v2.10.0 | GitOps持续部署 |
| **CI/CD** | Jenkins | v2.440 | 持续集成和持续部署 |
| **代码仓库** | GitLab CE | v18.6.1 | 代码托管和GitOps仓库 |
| **镜像仓库** | Harbor | v2.10.0 | 容器镜像仓库 |
| **监控** | Prometheus | v2.49.0 | 指标采集和告警 |
| **可视化** | Grafana | v10.2.0 | 监控数据可视化 |
| **日志** | ELK Stack | v8.11.0 | 日志采集和分析 |
| **负载均衡** | Nginx/HAProxy | Latest | 全局负载均衡 |
| **DNS** | CoreDNS | v1.11.1 | 集群内DNS解析 |
| **多集群管理** | KubeFed/Liqo | v0.11.0 | 多集群联邦 |

### 3.2 各组件部署方案

#### 3.2.1 Kubernetes集群部署

**集群1配置：**
```yaml
# group_vars/cluster1.yml
kubernetes_cluster_name: "cluster1-production"
kubernetes_version: "1.31.3"
kubernetes_pod_network_cidr: "10.244.1.0/16"
kubernetes_service_cidr: "10.96.1.0/12"
kube_vip_vip: "192.168.31.100"
```

**集群2配置：**
```yaml
# group_vars/cluster2.yml
kubernetes_cluster_name: "cluster2-staging"
kubernetes_version: "1.31.3"
kubernetes_pod_network_cidr: "10.244.2.0/16"
kubernetes_service_cidr: "10.96.2.0/12"
kube_vip_vip: "192.168.31.101"
```

#### 3.2.2 Harbor镜像仓库部署

在每个主节点部署Harbor镜像仓库：

```yaml
# playbook/harbor/deploy-harbor.yml
---
- name: Deploy Harbor on Cluster1 Master
  hosts: cluster1_first_master
  become: yes
  roles:
    - install-harbor
  vars:
    harbor_hostname: "registry.cluster1.local"
    harbor_http_port: 5000
    harbor_https_port: 5443
    harbor_admin_password: "Harbor12345"
    harbor_data_volume: "/data/harbor"

- name: Deploy Harbor on Cluster2 Master
  hosts: cluster2_first_master
  become: yes
  roles:
    - install-harbor
  vars:
    harbor_hostname: "registry.cluster2.local"
    harbor_http_port: 5000
    harbor_https_port: 5443
    harbor_admin_password: "Harbor12345"
    harbor_data_volume: "/data/harbor"
```

#### 3.2.3 Istio服务网格部署

```yaml
# playbook/istio/deploy-istio.yml
---
- name: Deploy Istio on Cluster1
  hosts: cluster1_first_master
  become: yes
  tasks:
    - name: Download Istio
      get_url:
        url: "https://github.com/istio/istio/releases/download/1.21.0/istio-1.21.0-linux-amd64.tar.gz"
        dest: /tmp/istio.tar.gz
    
    - name: Extract Istio
      unarchive:
        src: /tmp/istio.tar.gz
        dest: /usr/local/bin
        remote_src: yes
    
    - name: Install Istio
      shell: |
        export PATH=$PATH:/usr/local/bin/istio-1.21.0/bin
        istioctl install --set profile=default -y
    
    - name: Enable Istio injection for default namespace
      shell: kubectl label namespace default istio-injection=enabled --overwrite

- name: Deploy Istio on Cluster2
  hosts: cluster2_first_master
  become: yes
  tasks:
    - name: Install Istio
      shell: |
        export PATH=$PATH:/usr/local/bin/istio-1.21.0/bin
        istioctl install --set profile=default -y
    
    - name: Enable Istio injection for default namespace
      shell: kubectl label namespace default istio-injection=enabled --overwrite
```

#### 3.2.4 ArgoCD多集群部署

```yaml
# playbook/argocd/deploy-argocd.yml
---
- name: Deploy ArgoCD on Cluster1
  hosts: cluster1_first_master
  become: yes
  tasks:
    - name: Create ArgoCD namespace
      shell: kubectl create namespace argocd
    
    - name: Install ArgoCD
      shell: |
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    - name: Get ArgoCD initial password
      shell: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
      register: argocd_password
    
    - name: Add Cluster2 to ArgoCD
      shell: |
        argocd login --grpc-web localhost:8080 --username admin --password {{ argocd_password.stdout }}
        argocd cluster add cluster2-staging --kubeconfig /root/.kube/config-cluster2
```

---

## 4. 网络架构设计

### 4.1 多集群网络通信方案

```mermaid
graph LR
    subgraph "集群1网络"
        C1Pod[Pod: 10.244.1.0/16]
        C1Svc[Service: 10.96.1.0/12]
        C1Node[Node: 192.168.31.30-41]
    end
    
    subgraph "集群2网络"
        C2Pod[Pod: 10.244.2.0/16]
        C2Svc[Service: 10.96.2.0/12]
        C2Node[Node: 192.168.31.31-43]
    end
    
    subgraph "多集群连接"
        VPN[VPN隧道/IPSec<br/>或Submariner]
        DNS[跨集群DNS解析]
    end
    
    C1Pod --> C1Svc
    C1Svc --> C1Node
    C2Pod --> C2Svc
    C2Svc --> C2Node
    
    C1Node <--> VPN
    VPN <--> C2Node
    
    C1Svc <--> DNS
    DNS <--> C2Svc
```

### 4.2 服务发现架构

**Istio多集群服务发现配置：**

```yaml
# istio-multicluster/cluster1.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
    pilot:
      env:
        EXTERNAL_ISTIOD: "true"
---
# istio-multicluster/cluster2.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster2
      network: network1
```

**跨集群ServiceEntry：**

```yaml
# 从集群1访问集群2的服务
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: gaamingblog-cluster2
  namespace: default
spec:
  hosts:
  - gaamingblog.cluster2.global
  location: MESH_INTERNAL
  ports:
  - name: http
    number: 80
    protocol: HTTP
  resolution: DNS
  endpoints:
  - address: 192.168.31.101  # 集群2的Ingress Gateway
    ports:
      http: 15443
```

### 4.3 全局负载均衡方案

**Nginx全局负载均衡配置：**

```nginx
# /etc/nginx/nginx.conf
# 生产环境负载均衡
upstream gaamingblog_prod_backend {
    least_conn;
    server 192.168.31.100:32080 weight=5;  # 集群1 Prod Ingress
    server 192.168.31.101:32080 weight=5;  # 集群2 Prod Ingress
    
    # 健康检查
    keepalive 32;
}

# Canary环境负载均衡
upstream gaamingblog_canary_backend {
    least_conn;
    server 192.168.31.100:32081 weight=5;  # 集群1 Canary Ingress
    server 192.168.31.101:32081 weight=5;  # 集群2 Canary Ingress
    
    # 健康检查
    keepalive 32;
}

# 生产环境HTTP服务器
server {
    listen 80;
    server_name blog.gaaming.com;
    
    # 重定向到HTTPS
    return 301 https://$server_name$request_uri;
}

# 生产环境HTTPS服务器
server {
    listen 443 ssl http2;
    server_name blog.gaaming.com;
    
    ssl_certificate /etc/nginx/ssl/blog.gaaming.com.crt;
    ssl_certificate_key /etc/nginx/ssl/blog.gaaming.com.key;
    
    # SSL配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Gzip压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    location / {
        proxy_pass http://gaamingblog_prod_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 超时配置
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 健康检查
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK\n";
    }
}

# Canary环境HTTP服务器
server {
    listen 80;
    server_name canary.blog.gaaming.com;
    
    # 重定向到HTTPS
    return 301 https://$server_name$request_uri;
}

# Canary环境HTTPS服务器
server {
    listen 443 ssl http2;
    server_name canary.blog.gaaming.com;
    
    ssl_certificate /etc/nginx/ssl/blog.gaaming.com.crt;
    ssl_certificate_key /etc/nginx/ssl/blog.gaaming.com.key;
    
    # SSL配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Gzip压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    location / {
        proxy_pass http://gaamingblog_canary_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 超时配置
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 健康检查
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK\n";
    }
}
```

**Istio Ingress Gateway配置：**

```yaml
# 生产环境Gateway配置
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: gaamingblog-prod-gateway
  namespace: gaamingblog-prod
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "blog.gaaming.com"
    tls:
      httpsRedirect: true
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: gaamingblog-prod-tls
    hosts:
    - "blog.gaaming.com"
---
# 生产环境VirtualService配置
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: gaamingblog-prod-vs
  namespace: gaamingblog-prod
spec:
  hosts:
  - "blog.gaaming.com"
  gateways:
  - gaamingblog-prod-gateway
  http:
  - route:
    - destination:
        host: gaamingblog-prod-service
        port:
          number: 80
      weight: 100
---
# Canary环境Gateway配置
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: gaamingblog-canary-gateway
  namespace: gaamingblog-canary
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "canary.blog.gaaming.com"
    tls:
      httpsRedirect: true
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: gaamingblog-canary-tls
    hosts:
    - "canary.blog.gaaming.com"
---
# Canary环境VirtualService配置
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: gaamingblog-canary-vs
  namespace: gaamingblog-canary
spec:
  hosts:
  - "canary.blog.gaaming.com"
  gateways:
  - gaamingblog-canary-gateway
  http:
  - route:
    - destination:
        host: gaamingblog-canary-service
        port:
          number: 80
      weight: 100
```

---

## 5. GitOps工作流设计

### 5.1 GitOps仓库结构

```
gaamingblog-gitops/
├── README.md
├── clusters/
│   ├── cluster1/
│   │   ├── prod/
│   │   │   ├── apps/
│   │   │   │   └── gaamingblog/
│   │   │   │       ├── Chart.yaml
│   │   │   │       ├── values.yaml
│   │   │   │       └── templates/
│   │   │   │           ├── deployment.yaml
│   │   │   │           ├── service.yaml
│   │   │   │           ├── configmap.yaml
│   │   │   │           └── istio/
│   │   │   │               ├── virtualservice.yaml
│   │   │   │               └── destinationrule.yaml
│   │   │   └── kustomization.yaml
│   │   └── canary/
│   │       ├── apps/
│   │       │   └── gaamingblog/
│   │       │       ├── Chart.yaml
│   │       │       ├── values.yaml
│   │       │       └── templates/
│   │       └── kustomization.yaml
│   └── cluster2/
│       ├── prod/
│       │   ├── apps/
│       │   │   └── gaamingblog/
│       │   │       ├── Chart.yaml
│       │   │       ├── values.yaml
│       │   │       └── templates/
│       │   └── kustomization.yaml
│       └── canary/
│           ├── apps/
│           │   └── gaamingblog/
│           │       ├── Chart.yaml
│           │       ├── values.yaml
│           │       └── templates/
│           └── kustomization.yaml
├── apps/
│   └── gaamingblog/
│       ├── base/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── kustomization.yaml
│       └── overlays/
│           ├── prod/
│           │   ├── kustomization.yaml
│           │   ├── patches/
│           │   │   └── deployment-replicas.yaml
│           │   └── values.yaml
│           └── canary/
│               ├── kustomization.yaml
│               └── values.yaml
└── infrastructure/
    └── argocd/
        ├── projects/
        │   ├── gaamingblog-prod-project.yaml
        │   └── gaamingblog-canary-project.yaml
        └── applications/
            ├── cluster1-prod-gaamingblog.yaml
            ├── cluster1-canary-gaamingblog.yaml
            ├── cluster2-prod-gaamingblog.yaml
            └── cluster2-canary-gaamingblog.yaml
```

### 5.2 ArgoCD Application配置

```yaml
# infrastructure/argocd/applications/cluster1-prod-gaamingblog.yaml
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
    repoURL: https://gitlab.gaaming.com/gaamingblog/gitops.git
    targetRevision: HEAD
    path: clusters/cluster1/prod/apps/gaamingblog
    helm:
      valueFiles:
      - values.yaml
  destination:
    server: https://192.168.31.100:6443  # 集群1 API Server
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
---
# infrastructure/argocd/applications/cluster1-canary-gaamingblog.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gaamingblog-cluster1-canary
  namespace: argocd
spec:
  project: gaamingblog-canary
  source:
    repoURL: https://gitlab.gaaming.com/gaamingblog/gitops.git
    targetRevision: HEAD
    path: clusters/cluster1/canary/apps/gaamingblog
  destination:
    server: https://192.168.31.100:6443  # 集群1 API Server
    namespace: gaamingblog-canary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
# infrastructure/argocd/applications/cluster2-prod-gaamingblog.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gaamingblog-cluster2-prod
  namespace: argocd
spec:
  project: gaamingblog-prod
  source:
    repoURL: https://gitlab.gaaming.com/gaamingblog/gitops.git
    targetRevision: HEAD
    path: clusters/cluster2/prod/apps/gaamingblog
  destination:
    server: https://192.168.31.101:6443  # 集群2 API Server
    namespace: gaamingblog-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
# infrastructure/argocd/applications/cluster2-canary-gaamingblog.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gaamingblog-cluster2-canary
  namespace: argocd
spec:
  project: gaamingblog-canary
  source:
    repoURL: https://gitlab.gaaming.com/gaamingblog/gitops.git
    targetRevision: HEAD
    path: clusters/cluster2/canary/apps/gaamingblog
  destination:
    server: https://192.168.31.101:6443  # 集群2 API Server
    namespace: gaamingblog-canary
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**ArgoCD Project配置**：

```yaml
# infrastructure/argocd/projects/gaamingblog-prod-project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gaamingblog-prod
  namespace: argocd
spec:
  description: GaamingBlog Production Environment
  sourceRepos:
  - 'https://gitlab.gaaming.com/gaamingblog/gitops.git'
  destinations:
  - namespace: gaamingblog-prod
    server: https://192.168.31.100:6443
  - namespace: gaamingblog-prod
    server: https://192.168.31.101:6443
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
---
# infrastructure/argocd/projects/gaamingblog-canary-project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gaamingblog-canary
  namespace: argocd
spec:
  description: GaamingBlog Canary/Development Environment
  sourceRepos:
  - 'https://gitlab.gaaming.com/gaamingblog/gitops.git'
  destinations:
  - namespace: gaamingblog-canary
    server: https://192.168.31.100:6443
  - namespace: gaamingblog-canary
    server: https://192.168.31.101:6443
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
```

### 5.3 GaamingBlog Helm Chart

```yaml
# clusters/cluster1/prod/apps/gaamingblog/Chart.yaml
apiVersion: v2
name: gaamingblog
description: GaamingBlog application Helm chart
type: application
version: 1.0.0
appVersion: "1.0.0"
---
# clusters/cluster1/prod/apps/gaamingblog/values.yaml
replicaCount: 2

image:
  repository: registry.cluster1.local/gaamingblog/gaamingblog
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

# Istio配置
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

# 数据库配置
database:
  type: mysql
  host: mysql-service
  port: 3306
  name: gaamingblog_prod

# 环境标识
environment: prod

# Namespace
namespace: gaamingblog-prod
---
# clusters/cluster1/canary/apps/gaamingblog/values.yaml
replicaCount: 1

image:
  repository: registry.cluster1.local/gaamingblog/gaamingblog
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

# Istio配置
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

# 数据库配置
database:
  type: mysql
  host: mysql-service
  port: 3306
  name: gaamingblog_canary

# 环境标识
environment: canary

# Namespace
namespace: gaamingblog-canary
```

```yaml
# clusters/cluster1-production/apps/gaamingblog/templates/deployment.yaml
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
        env:
        - name: DB_HOST
          value: {{ .Values.database.host }}
        - name: DB_PORT
          value: "{{ .Values.database.port }}"
        - name: DB_NAME
          value: {{ .Values.database.name }}
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
```

---

## 6. 双环境部署架构设计

### 6.1 环境架构概览

本设计在每个Kubernetes集群中同时部署两个独立的环境：

#### 6.1.1 环境定义

| 环境 | Namespace | 域名 | 用途 | 副本数 | 资源配置 |
|------|-----------|------|------|--------|----------|
| **GaamingBlog-Prod** | `gaamingblog-prod` | `blog.gaaming.com` | 生产环境 | 2副本/集群 | 高配置 |
| **GaamingBlog-Canary** | `gaamingblog-canary` | `canary.blog.gaaming.com` | 开发/测试环境 | 1副本/集群 | 低配置 |

#### 6.1.2 双环境架构图

```mermaid
graph TB
    subgraph "用户访问"
        UserProd[用户访问生产环境<br/>blog.gaaming.com]
        UserCanary[用户访问开发环境<br/>canary.blog.gaaming.com]
    end

    subgraph "全局负载均衡"
        GLB[Nginx全局负载均衡器]
    end

    subgraph "集群1"
        subgraph "生产环境Namespace"
            Prod1[gaamingblog-prod<br/>副本: 2<br/>资源: 高]
        end
        subgraph "开发环境Namespace"
            Canary1[gaamingblog-canary<br/>副本: 1<br/>资源: 低]
        end
    end

    subgraph "集群2"
        subgraph "生产环境Namespace"
            Prod2[gaamingblog-prod<br/>副本: 2<br/>资源: 高]
        end
        subgraph "开发环境Namespace"
            Canary2[gaamingblog-canary<br/>副本: 1<br/>资源: 低]
        end
    end

    UserProd --> GLB
    UserCanary --> GLB
    GLB -->|Prod流量| Prod1
    GLB -->|Prod流量| Prod2
    GLB -->|Canary流量| Canary1
    GLB -->|Canary流量| Canary2
```

### 6.2 环境隔离策略

#### 6.2.1 Namespace隔离

每个环境使用独立的Namespace，实现资源隔离：

```yaml
# 生产环境Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: gaamingblog-prod
  labels:
    environment: production
    app: gaamingblog
---
# 开发环境Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: gaamingblog-canary
  labels:
    environment: canary
    app: gaamingblog
```

#### 6.2.2 资源配额限制

```yaml
# 生产环境资源配额
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
# 开发环境资源配额
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
```

#### 6.2.3 网络策略隔离

```yaml
# 生产环境网络策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gaamingblog-prod-network-policy
  namespace: gaamingblog-prod
spec:
  podSelector:
    matchLabels:
      app: gaamingblog
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 3306
---
# 开发环境网络策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gaamingblog-canary-network-policy
  namespace: gaamingblog-canary
spec:
  podSelector:
    matchLabels:
      app: gaamingblog
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 3306
```

### 6.3 数据库隔离

#### 6.3.1 数据库架构

```yaml
# 生产环境数据库配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: gaamingblog-prod-db-config
  namespace: gaamingblog-prod
data:
  database-name: "gaamingblog_prod"
  database-host: "mysql-service"
  database-port: "3306"
---
# 开发环境数据库配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: gaamingblog-canary-db-config
  namespace: gaamingblog-canary
data:
  database-name: "gaamingblog_canary"
  database-host: "mysql-service"
  database-port: "3306"
```

#### 6.3.2 数据库初始化脚本

```sql
-- 创建生产环境数据库
CREATE DATABASE IF NOT EXISTS gaamingblog_prod
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- 创建开发环境数据库
CREATE DATABASE IF NOT EXISTS gaamingblog_canary
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- 创建应用用户
CREATE USER 'gaamingblog'@'%' IDENTIFIED BY 'password';

-- 授权
GRANT ALL PRIVILEGES ON gaamingblog_prod.* TO 'gaamingblog'@'%';
GRANT ALL PRIVILEGES ON gaamingblog_canary.* TO 'gaamingblog'@'%';

FLUSH PRIVILEGES;
```

### 6.4 部署流程设计

#### 6.4.1 开发流程

```mermaid
sequenceDiagram
    participant Dev as 开发人员
    participant Git as GitLab
    participant Jenkins as Jenkins
    participant ArgoCD as ArgoCD
    participant Canary as Canary环境
    participant Prod as Prod环境

    Dev->>Git: 提交代码到feature分支
    Git->>Jenkins: 触发CI Pipeline
    Jenkins->>Jenkins: 构建和测试
    Jenkins->>Git: 合并到main分支
    Git->>ArgoCD: 触发CD Pipeline
    
    Note over ArgoCD,Canary: 部署到Canary环境
    ArgoCD->>Canary: 部署新版本
    Dev->>Canary: 测试验证
    
    Note over Dev,Prod: 验证通过后部署到生产
    Dev->>Jenkins: 手动触发生产部署
    Jenkins->>ArgoCD: 更新Prod配置
    ArgoCD->>Prod: 部署到生产环境
    Dev->>Prod: 验证生产环境
```

#### 6.4.2 部署策略

**Canary环境部署策略**：
- 自动部署：代码合并到main分支后自动部署
- 快速迭代：支持频繁部署
- 资源限制：使用较低的资源配置
- 数据隔离：使用独立的数据库

**Prod环境部署策略**：
- 手动确认：需要人工确认才能部署
- 蓝绿部署：支持快速回滚
- 高可用：多副本部署
- 资源充足：使用较高的资源配置

### 6.5 监控和告警

#### 6.5.1 环境监控指标

```yaml
# Prometheus监控配置 - 区分环境
- job_name: 'gaamingblog-prod'
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
          - gaamingblog-prod
  relabel_configs:
    - source_labels: [__meta_kubernetes_namespace]
      target_label: environment
      replacement: prod

- job_name: 'gaamingblog-canary'
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
          - gaamingblog-canary
  relabel_configs:
    - source_labels: [__meta_kubernetes_namespace]
      target_label: environment
      replacement: canary
```

#### 6.5.2 环境告警规则

```yaml
# 生产环境告警 - 更严格
- alert: GaamingBlogProdHighErrorRate
  expr: |
    sum(rate(gaamingblog_http_requests_total{status=~"5..",environment="prod"}[5m])) 
    / 
    sum(rate(gaamingblog_http_requests_total{environment="prod"}[5m])) 
    > 0.01
  for: 2m
  labels:
    severity: critical
    environment: prod
  annotations:
    summary: "生产环境错误率过高"
    description: "生产环境错误率超过1%"

# 开发环境告警 - 相对宽松
- alert: GaamingBlogCanaryHighErrorRate
  expr: |
    sum(rate(gaamingblog_http_requests_total{status=~"5..",environment="canary"}[5m])) 
    / 
    sum(rate(gaamingblog_http_requests_total{environment="canary"}[5m])) 
    > 0.05
  for: 10m
  labels:
    severity: warning
    environment: canary
  annotations:
    summary: "开发环境错误率过高"
    description: "开发环境错误率超过5%"
```

### 6.6 成本优化

#### 6.6.1 资源配置对比

| 环境 | CPU请求 | CPU限制 | 内存请求 | 内存限制 | 副本数 | 总成本估算 |
|------|---------|---------|----------|----------|--------|-----------|
| Prod (每集群) | 500m × 2 | 1 core × 2 | 512Mi × 2 | 1Gi × 2 | 2 | 高 |
| Canary (每集群) | 150m × 1 | 300m × 1 | 128Mi × 1 | 256Mi × 1 | 1 | 低 |
| **总计 (双集群)** | 1.3 cores | 2.6 cores | 1.152Gi | 2.304Gi | 6 | 中 |

#### 6.6.2 自动扩缩容策略

```yaml
# 生产环境HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gaamingblog-prod-hpa
  namespace: gaamingblog-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gaamingblog-prod
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
# 开发环境不启用HPA（固定1副本）
```

---

## 7. CI/CD流水线设计

### 7.1 Jenkins Pipeline（双环境部署）

```groovy
// pipelines/GaamingBlog-Deploy.Jenkinsfile
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
            defaultValue: true,
            description: '是否同时部署到两个集群'
        )
    }
    
    environment {
        GITLAB_REPO = 'git@gitlab.gaaming.com:gaamingblog/gaamingblog.git'
        GITOPS_REPO = 'git@gitlab.gaaming.com:gaamingblog/gitops.git'
        REGISTRY_CLUSTER1 = 'registry.cluster1.local'
        REGISTRY_CLUSTER2 = 'registry.cluster2.local'
        IMAGE_NAME = 'gaamingblog/gaamingblog'
        DOCKER_CREDENTIALS = 'harbor-credentials'
        GIT_CREDENTIALS = 'gitlab-ssh-key'
    }
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', credentialsId: "${GIT_CREDENTIALS}", url: "${GITLAB_REPO}"
                script {
                    env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    env.VERSION = sh(returnStdout: true, script: 'cat VERSION').trim()
                    env.ENV_TAG = "${params.DEPLOY_ENV}-${env.IMAGE_TAG}"
                }
            }
        }
        
        stage('Build & Test') {
            parallel {
                stage('Build') {
                    steps {
                        sh '''
                            docker build -t ${REGISTRY_CLUSTER1}/${IMAGE_NAME}:${ENV_TAG} .
                            docker build -t ${REGISTRY_CLUSTER2}/${IMAGE_NAME}:${ENV_TAG} .
                        '''
                    }
                }
                stage('Unit Test') {
                    steps {
                        sh 'npm test'
                    }
                }
                stage('Code Quality') {
                    steps {
                        sh 'sonar-scanner'
                    }
                }
            }
        }
        
        stage('Push Images') {
            parallel {
                stage('Push to Cluster1 Registry') {
                    steps {
                        withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS}", usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                            sh '''
                                docker login ${REGISTRY_CLUSTER1} -u ${USERNAME} -p ${PASSWORD}
                                docker push ${REGISTRY_CLUSTER1}/${IMAGE_NAME}:${ENV_TAG}
                                docker tag ${REGISTRY_CLUSTER1}/${IMAGE_NAME}:${ENV_TAG} ${REGISTRY_CLUSTER1}/${IMAGE_NAME}:${DEPLOY_ENV}-latest
                                docker push ${REGISTRY_CLUSTER1}/${IMAGE_NAME}:${DEPLOY_ENV}-latest
                            '''
                        }
                    }
                }
                stage('Push to Cluster2 Registry') {
                    steps {
                        withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS}", usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
                            sh '''
                                docker login ${REGISTRY_CLUSTER2} -u ${USERNAME} -p ${PASSWORD}
                                docker push ${REGISTRY_CLUSTER2}/${IMAGE_NAME}:${ENV_TAG}
                                docker tag ${REGISTRY_CLUSTER2}/${IMAGE_NAME}:${ENV_TAG} ${REGISTRY_CLUSTER2}/${IMAGE_NAME}:${DEPLOY_ENV}-latest
                                docker push ${REGISTRY_CLUSTER2}/${IMAGE_NAME}:${DEPLOY_ENV}-latest
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Deploy to Canary Environment') {
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
                        
                        # 更新集群1 Canary环境
                        sed -i "s|tag: .*|tag: ${ENV_TAG}|g" clusters/cluster1/canary/apps/gaamingblog/values.yaml
                        
                        # 更新集群2 Canary环境
                        if [ "${DEPLOY_TO_BOTH_CLUSTERS}" = "true" ]; then
                            sed -i "s|tag: .*|tag: ${ENV_TAG}|g" clusters/cluster2/canary/apps/gaamingblog/values.yaml
                        fi
                        
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
                    // 等待ArgoCD同步完成
                    sh 'sleep 30'
                    
                    // 运行集成测试
                    sh '''
                        # 健康检查
                        curl -f http://canary.blog.gaaming.com/health || exit 1
                        
                        # 运行集成测试
                        npm run test:integration -- --env canary
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
                    // 生产环境需要人工确认
                    input message: '确认部署到生产环境?', ok: '确认部署'
                    
                    sh '''
                        cd gitops-repo
                        
                        # 更新集群1生产环境
                        sed -i "s|tag: .*|tag: ${ENV_TAG}|g" clusters/cluster1/prod/apps/gaamingblog/values.yaml
                        
                        # 更新集群2生产环境
                        if [ "${DEPLOY_TO_BOTH_CLUSTERS}" = "true" ]; then
                            sed -i "s|tag: .*|tag: ${ENV_TAG}|g" clusters/cluster2/prod/apps/gaamingblog/values.yaml
                        fi
                        
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
                    // 等待ArgoCD同步完成
                    sh 'sleep 60'
                    
                    // 健康检查
                    sh '''
                        # 检查集群1
                        curl -f http://blog.gaaming.com/health || exit 1
                        
                        # 运行冒烟测试
                        npm run test:smoke -- --env prod
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
            slackSend channel: '#deployments', color: 'good', 
                message: "部署成功: ${ENV_TAG} 到 ${params.DEPLOY_ENV} 环境"
        }
        failure {
            slackSend channel: '#deployments', color: 'danger', 
                message: "部署失败: ${ENV_TAG} 到 ${params.DEPLOY_ENV} 环境"
            script {
                // 自动回滚
                sh '''
                    cd gitops-repo
                    git reset --hard HEAD~1
                    git push -f origin main
                '''
            }
        }
    }
}
```

### 6.2 金丝雀发布Istio配置

```yaml
# clusters/cluster1-production/apps/gaamingblog/templates/istio/destinationrule.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: gaamingblog-destination
  namespace: default
spec:
  host: gaamingblog-service
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
---
# clusters/cluster1-production/apps/gaamingblog/templates/istio/virtualservice.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: gaamingblog-canary
  namespace: default
spec:
  hosts:
  - gaamingblog-service
  http:
  - route:
    - destination:
        host: gaamingblog-service
        subset: stable
      weight: {{ .Values.canary.weight | default 0 }}
    {{- if .Values.canary.enabled }}
    - destination:
        host: gaamingblog-service
        subset: canary
      weight: {{ .Values.canary.weight }}
    {{- end }}
```

---

## 7. 高可用性和容灾方案

### 7.1 高可用架构设计

```mermaid
graph TB
    subgraph "高可用架构"
        subgraph "应用层HA"
            Pod1[Pod Replica 1]
            Pod2[Pod Replica 2]
            Pod3[Pod Replica 3]
        end
        
        subgraph "集群层HA"
            Cluster1[集群1 - 生产]
            Cluster2[集群2 - 预发]
        end
        
        subgraph "数据层HA"
            MySQL[MySQL主从]
            MongoDB[MongoDB副本集]
        end
        
        subgraph "负载均衡层HA"
            GLB1[GLB Primary]
            GLB2[GLB Backup]
        end
    end
    
    GLB1 --> Cluster1
    GLB1 --> Cluster2
    GLB2 -.->|Backup| Cluster1
    GLB2 -.->|Backup| Cluster2
    
    Cluster1 --> Pod1
    Cluster1 --> Pod2
    Cluster2 --> Pod3
    
    Pod1 --> MySQL
    Pod2 --> MySQL
    Pod3 --> MySQL
    
    Pod1 --> MongoDB
    Pod2 --> MongoDB
    Pod3 --> MongoDB
```

### 7.2 容灾方案

#### 7.2.1 数据备份策略

```yaml
# backup/backup-policy.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mysql-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # 每天凌晨2点备份
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mysql-backup
            image: mysql:8.0
            command:
            - /bin/sh
            - -c
            - |
              mysqldump -h mysql-service -u root -p${MYSQL_ROOT_PASSWORD} \
                --all-databases --single-transaction --routines --triggers \
                | gzip > /backup/mysql-backup-$(date +%Y%m%d-%H%M%S).sql.gz
              
              # 上传到远程存储
              aws s3 cp /backup/mysql-backup-*.sql.gz s3://gaamingblog-backup/mysql/
              
              # 清理7天前的备份
              find /backup -name "*.sql.gz" -mtime +7 -delete
            env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: root-password
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup
  namespace: default
spec:
  schedule: "0 3 * * *"  # 每天凌晨3点备份
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mongodb-backup
            image: mongo:7.0
            command:
            - /bin/sh
            - -c
            - |
              mongodump --host mongodb-service --port 27017 \
                --username ${MONGO_USER} --password ${MONGO_PASSWORD} \
                --out /backup/mongodb-backup-$(date +%Y%m%d-%H%M%S)
              
              # 压缩并上传
              tar -czf /backup/mongodb-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
                -C /backup mongodb-backup-$(date +%Y%m%d-%H%M%S)
              
              aws s3 cp /backup/mongodb-backup-*.tar.gz s3://gaamingblog-backup/mongodb/
            env:
            - name: MONGO_USER
              valueFrom:
                secretKeyRef:
                  name: mongodb-secret
                  key: username
            - name: MONGO_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mongodb-secret
                  key: password
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

#### 7.2.2 灾难恢复流程

```yaml
# disaster-recovery/failover.yaml
# 集群故障自动切换配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: failover-config
  namespace: default
data:
  failover.sh: |
    #!/bin/bash
    
    # 检测集群1健康状态
    CLUSTER1_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" https://192.168.31.100:6443/healthz)
    
    if [ "$CLUSTER1_HEALTH" != "200" ]; then
      echo "Cluster1 is down, failing over to Cluster2..."
      
      # 更新DNS记录
      aws route53 change-resource-record-sets \
        --hosted-zone-id $HOSTED_ZONE_ID \
        --change-batch '{
          "Changes": [{
            "Action": "UPSERT",
            "ResourceRecordSet": {
              "Name": "blog.gaaming.com",
              "Type": "A",
              "TTL": 60,
              "ResourceRecords": [{"Value": "192.168.31.101"}]
            }
          }]
        }'
      
      # 更新负载均衡器配置
      kubectl config use-context cluster2
      kubectl scale deployment gaamingblog --replicas=4 -n default
      
      # 发送告警
      curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"Cluster1 failed over to Cluster2"}' \
        $SLACK_WEBHOOK_URL
    fi
```

### 7.3 监控和告警

```yaml
# monitoring/prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gaamingblog-alerts
  namespace: monitoring
spec:
  groups:
  - name: gaamingblog.rules
    rules:
    - alert: HighErrorRate
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
        /
        sum(rate(http_requests_total[5m])) by (service)
        > 0.05
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: High error rate on {{ $labels.service }}
        description: Error rate is {{ $value | humanizePercentage }}
    
    - alert: PodCrashLooping
      expr: |
        rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: Pod {{ $labels.pod }} is crash looping
        description: Pod has restarted {{ $value }} times in the last 15 minutes
    
    - alert: ClusterDown
      expr: up{job="kubernetes-apiservers"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: Cluster {{ $labels.cluster }} is down
        description: API server is not responding
    
    - alert: HighMemoryUsage
      expr: |
        (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
        / node_memory_MemTotal_bytes > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: High memory usage on {{ $labels.instance }}
        description: Memory usage is {{ $value | humanizePercentage }}
```

---

## 8. 多集群监控系统设计

### 8.1 监控架构总览

#### 8.1.1 Prometheus多集群联邦架构

```mermaid
graph TB
    subgraph "监控中心"
        PrometheusCentral[Prometheus中央服务器<br/>192.168.31.80<br/>联邦查询 + 长期存储]
        Grafana[Grafana可视化<br/>192.168.31.60<br/>统一仪表板]
        AlertManager[AlertManager告警<br/>192.168.31.81]
    end

    subgraph "集群1监控"
        Prometheus1[Prometheus集群1<br/>192.168.31.30<br/>本地监控]
        NodeExporter1[Node Exporter<br/>所有节点]
        KubeStateMetrics1[kube-state-metrics<br/>集群1]
        IstioMetrics1[Istio Metrics<br/>服务网格指标]
        AppMetrics1[GaamingBlog Metrics<br/>应用指标]
    end

    subgraph "集群2监控"
        Prometheus2[Prometheus集群2<br/>192.168.31.31<br/>本地监控]
        NodeExporter2[Node Exporter<br/>所有节点]
        KubeStateMetrics2[kube-state-metrics<br/>集群2]
        IstioMetrics2[Istio Metrics<br/>服务网格指标]
        AppMetrics2[GaamingBlog Metrics<br/>应用指标]
    end

    Prometheus1 -->|联邦抓取| PrometheusCentral
    Prometheus2 -->|联邦抓取| PrometheusCentral
    PrometheusCentral --> Grafana
    PrometheusCentral --> AlertManager
    
    NodeExporter1 --> Prometheus1
    KubeStateMetrics1 --> Prometheus1
    IstioMetrics1 --> Prometheus1
    AppMetrics1 --> Prometheus1
    
    NodeExporter2 --> Prometheus2
    KubeStateMetrics2 --> Prometheus2
    IstioMetrics2 --> Prometheus2
    AppMetrics2 --> Prometheus2
```

#### 8.1.2 监控数据流

```mermaid
sequenceDiagram
    participant App as GaamingBlog应用
    participant Istio as Istio代理
    participant Node as Node Exporter
    participant KSM as kube-state-metrics
    participant Prom as Prometheus(集群)
    participant Central as Prometheus(中央)
    participant Grafana as Grafana
    participant Alert as AlertManager

    App->>Istio: 暴露/metrics端点
    Istio->>Prom: 提供服务网格指标
    Node->>Prom: 提供节点指标
    KSM->>Prom: 提供K8s对象指标
    App->>Prom: 提供应用指标
    
    Prom->>Central: 联邦抓取(每15s)
    Central->>Grafana: 提供查询接口
    Central->>Alert: 发送告警
    
    Grafana->>Central: 查询多集群数据
    Grafana->>User: 展示统一仪表板
```

### 8.2 Prometheus部署方案

#### 8.2.1 中央Prometheus服务器配置

**部署位置**：独立服务器 192.168.31.80

**Ansible Playbook**：
```yaml
# playbook/monitoring/deploy-prometheus-central.yml
---
- name: Deploy Central Prometheus Server
  hosts: prometheus_server
  become: yes
  roles:
    - prometheus
  vars:
    prometheus_version: "2.49.0"
    prometheus_retention: "30d"
    prometheus_storage_retention_size: "50GB"
    prometheus_config_dir: "/etc/prometheus"
    prometheus_data_dir: "/var/lib/prometheus"
    
    prometheus_global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        monitor: 'central-prometheus'
    
    prometheus_federation:
      - name: 'cluster1-production'
        url: 'http://192.168.31.30:9090'
        labels:
          cluster: 'cluster1'
          environment: 'production'
      - name: 'cluster2-staging'
        url: 'http://192.168.31.31:9090'
        labels:
          cluster: 'cluster2'
          environment: 'staging'
```

**Prometheus配置文件**：
```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'central-prometheus'

# 告警规则文件
rule_files:
  - '/etc/prometheus/rules/*.yml'

# 联邦配置 - 从两个集群抓取数据
scrape_configs:
  # 联邦抓取集群1数据
  - job_name: 'federate-cluster1'
    scrape_interval: 15s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job="prometheus"}'
        - '{job="node-exporter"}'
        - '{job="kube-state-metrics"}'
        - '{job="kubernetes-pods"}'
        - '{job="istio-mesh"}'
        - '{job="gaamingblog"}'
    static_configs:
      - targets:
        - '192.168.31.30:9090'
        labels:
          cluster: 'cluster1'
          environment: 'production'

  # 联邦抓取集群2数据
  - job_name: 'federate-cluster2'
    scrape_interval: 15s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job="prometheus"}'
        - '{job="node-exporter"}'
        - '{job="kube-state-metrics"}'
        - '{job="kubernetes-pods"}'
        - '{job="istio-mesh"}'
        - '{job="gaamingblog"}'
    static_configs:
      - targets:
        - '192.168.31.31:9090'
        labels:
          cluster: 'cluster2'
          environment: 'staging'

  # 监控自身
  - job_name: 'prometheus-central'
    static_configs:
      - targets: ['localhost:9090']

# Alertmanager配置
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - '192.168.31.81:9093'
```

#### 8.2.2 集群Prometheus配置

**在每个集群的主节点部署Prometheus**：

```yaml
# playbook/monitoring/deploy-prometheus-cluster.yml
---
- name: Deploy Prometheus on Cluster1
  hosts: cluster1_first_master
  become: yes
  roles:
    - prometheus
  vars:
    prometheus_version: "2.49.0"
    prometheus_retention: "15d"
    prometheus_config_dir: "/etc/prometheus"
    prometheus_data_dir: "/var/lib/prometheus"
    
    prometheus_global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: 'cluster1'
        environment: 'production'

- name: Deploy Prometheus on Cluster2
  hosts: cluster2_first_master
  become: yes
  roles:
    - prometheus
  vars:
    prometheus_version: "2.49.0"
    prometheus_retention: "15d"
    prometheus_config_dir: "/etc/prometheus"
    prometheus_data_dir: "/var/lib/prometheus"
    
    prometheus_global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: 'cluster2'
        environment: 'staging'
```

**集群Prometheus配置文件**：
```yaml
# /etc/prometheus/prometheus.yml (集群1)
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'cluster1'
    environment: 'production'

rule_files:
  - '/etc/prometheus/rules/*.yml'

scrape_configs:
  # Node Exporter - 监控所有节点
  - job_name: 'node-exporter'
    static_configs:
      - targets:
        - '192.168.31.30:9100'  # Master节点
        - '192.168.31.40:9100'  # Worker1
        - '192.168.31.41:9100'  # Worker2
        labels:
          cluster: 'cluster1'

  # kube-state-metrics
  - job_name: 'kube-state-metrics'
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - kube-system
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: kube-state-metrics

  # Kubernetes API Server
  - job_name: 'kubernetes-apiservers'
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https

  # Kubernetes Nodes
  - job_name: 'kubernetes-nodes'
    kubernetes_sd_configs:
      - role: node
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)

  # Kubernetes Pods
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name

  # Istio控制平面
  - job_name: 'istiod'
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - istio-system
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: istiod

  # Istio Envoy指标
  - job_name: 'envoy-stats'
    metrics_path: /stats/prometheus
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: keep
        regex: istio-proxy

  # GaamingBlog应用监控
  - job_name: 'gaamingblog'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - default
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: keep
        regex: gaamingblog
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
```

### 8.3 Node Exporter部署

#### 8.3.1 在所有节点部署Node Exporter

```yaml
# playbook/monitoring/deploy-node-exporter.yml
---
- name: Deploy Node Exporter on all nodes
  hosts: allNodes
  become: yes
  roles:
    - node-exporter
  vars:
    node_exporter_version: "1.7.0"
    node_exporter_listen_address: "0.0.0.0:9100"
    node_exporter_enabled_collectors:
      - arp
      - bcache
      - bonding
      - btrfs
      - buddyinfo
      - conntrack
      - cpu
      - cpufreq
      - diskstats
      - drbd
      - edac
      - entropy
      - fibrechannel
      - filefd
      - filesystem
      - hwmon
      - infiniband
      - infiniband
      - ipvs
      - ksmd
      - loadavg
      - mdadm
      - meminfo
      - meminfo_numa
      - mountstats
      - netclass
      - netdev
      - netstat
      - nfs
      - nfsd
      - pressure
      - rapl
      - schedstat
      - sockstat
      - softnet
      - stat
      - thermal_zone
      - time
      - timex
      - udp_queues
      - uname
      - vmstat
      - xfs
      - zfs
```

**Node Exporter Systemd服务**：
```ini
# /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=0.0.0.0:9100 \
    --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/) \
    --collector.netclass.ignored-devices=^(veth.*)$$
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 8.4 kube-state-metrics部署

```yaml
# kubernetes-manifests/kube-state-metrics.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-state-metrics
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics
rules:
- apiGroups: [""]
  resources:
  - configmaps
  - secrets
  - nodes
  - pods
  - services
  - resourcequotas
  - replicationcontrollers
  - limitranges
  - persistentvolumeclaims
  - persistentvolumes
  - namespaces
  - endpoints
  verbs: ["list", "watch"]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources:
  - ingresses
  - networkpolicies
  verbs: ["list", "watch"]
- apiGroups: ["apps"]
  resources:
  - daemonsets
  - deployments
  - replicasets
  - statefulsets
  verbs: ["list", "watch"]
- apiGroups: ["batch"]
  resources:
  - cronjobs
  - jobs
  verbs: ["list", "watch"]
- apiGroups: ["autoscaling"]
  resources:
  - horizontalpodautoscalers
  verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-state-metrics
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: kube-state-metrics
  replicas: 1
  template:
    metadata:
      labels:
        app: kube-state-metrics
    spec:
      serviceAccountName: kube-state-metrics
      containers:
      - name: kube-state-metrics
        image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0
        ports:
        - name: http-metrics
          containerPort: 8080
        - name: telemetry
          containerPort: 8081
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          timeoutSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kube-state-metrics
  namespace: kube-system
  labels:
    app: kube-state-metrics
  annotations:
    prometheus.io/scrape: 'true'
    prometheus.io/port: '8080'
spec:
  ports:
  - name: http-metrics
    port: 8080
    targetPort: http-metrics
    protocol: TCP
  - name: telemetry
    port: 8081
    targetPort: telemetry
    protocol: TCP
  selector:
    app: kube-state-metrics
```

### 8.5 GaamingBlog应用监控配置

#### 8.5.1 应用暴露监控指标

在GaamingBlog应用中添加Prometheus指标暴露：

```yaml
# clusters/cluster1-production/apps/gaamingblog/templates/deployment.yaml
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
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: 80
          name: http
        - containerPort: 8080
          name: metrics
        env:
        - name: ENABLE_METRICS
          value: "true"
        - name: METRICS_PORT
          value: "8080"
```

#### 8.5.2 应用指标示例

GaamingBlog应用应该暴露以下指标：

```python
# 应用代码示例（Python/Flask）
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from flask import Flask, request, Response

app = Flask(__name__)

# 请求计数器
REQUEST_COUNT = Counter(
    'gaamingblog_http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status', 'cluster']
)

# 请求延迟直方图
REQUEST_LATENCY = Histogram(
    'gaamingblog_http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint', 'cluster']
)

# 活跃连接数
ACTIVE_CONNECTIONS = Gauge(
    'gaamingblog_active_connections',
    'Active connections',
    ['cluster']
)

# 数据库连接池
DB_CONNECTIONS = Gauge(
    'gaamingblog_db_connections',
    'Database connections',
    ['state', 'cluster']
)

# 缓存命中率
CACHE_HITS = Counter(
    'gaamingblog_cache_hits_total',
    'Cache hits',
    ['result', 'cluster']
)

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype='text/plain')

@app.before_request
def before_request():
    ACTIVE_CONNECTIONS.labels(cluster='cluster1').inc()

@app.after_request
def after_request(response):
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.endpoint,
        status=response.status_code,
        cluster='cluster1'
    ).inc()
    
    ACTIVE_CONNECTIONS.labels(cluster='cluster1').dec()
    
    return response
```

### 8.6 Grafana部署和配置

#### 8.6.1 Grafana部署

```yaml
# playbook/monitoring/deploy-grafana.yml
---
- name: Deploy Grafana
  hosts: grafana_server
  become: yes
  roles:
    - grafana
  vars:
    grafana_version: "10.2.0"
    grafana_port: 3000
    grafana_admin_user: "admin"
    grafana_admin_password: "admin123"
    grafana_data_dir: "/var/lib/grafana"
    grafana_plugins:
      - grafana-piechart-panel
      - grafana-clock-panel
      - grafana-worldmap-panel
    
    grafana_datasources:
      - name: 'Prometheus-Central'
        type: 'prometheus'
        access: 'proxy'
        url: 'http://192.168.31.80:9090'
        isDefault: true
        editable: false
```

#### 8.6.2 Grafana Dashboard配置

**GaamingBlog服务状态Dashboard**：

```json
{
  "dashboard": {
    "title": "GaamingBlog - 多集群服务监控",
    "uid": "gaamingblog-multicluster",
    "tags": ["gaamingblog", "multicluster", "istio"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "全局请求概览",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "sum(rate(gaamingblog_http_requests_total[5m]))",
            "legendFormat": "总请求/秒"
          }
        ],
        "options": {
          "colorMode": "value",
          "graphMode": "area"
        }
      },
      {
        "title": "平均响应时间",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [
          {
            "expr": "histogram_quantile(0.50, sum(rate(gaamingblog_http_request_duration_seconds_bucket[5m])) by (le))",
            "legendFormat": "P50"
          }
        ]
      },
      {
        "title": "错误率",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "sum(rate(gaamingblog_http_requests_total{status=~\"5..\"}[5m])) / sum(rate(gaamingblog_http_requests_total[5m])) * 100",
            "legendFormat": "错误率 %"
          }
        ],
        "thresholds": [
          {"value": 0, "color": "green"},
          {"value": 1, "color": "yellow"},
          {"value": 5, "color": "red"}
        ]
      },
      {
        "title": "活跃连接数",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0},
        "targets": [
          {
            "expr": "sum(gaamingblog_active_connections)",
            "legendFormat": "连接数"
          }
        ]
      },
      {
        "title": "集群请求分布",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "targets": [
          {
            "expr": "sum(rate(gaamingblog_http_requests_total{cluster=\"cluster1\"}[5m])) by (cluster)",
            "legendFormat": "集群1 - 生产"
          },
          {
            "expr": "sum(rate(gaamingblog_http_requests_total{cluster=\"cluster2\"}[5m])) by (cluster)",
            "legendFormat": "集群2 - 预发"
          }
        ],
        "yaxes": [
          {"format": "reqps", "label": "请求/秒"}
        ]
      },
      {
        "title": "响应时间分布",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
        "targets": [
          {
            "expr": "histogram_quantile(0.50, sum(rate(gaamingblog_http_request_duration_seconds_bucket{cluster=\"cluster1\"}[5m])) by (le))",
            "legendFormat": "P50 - 集群1"
          },
          {
            "expr": "histogram_quantile(0.95, sum(rate(gaamingblog_http_request_duration_seconds_bucket{cluster=\"cluster1\"}[5m])) by (le))",
            "legendFormat": "P95 - 集群1"
          },
          {
            "expr": "histogram_quantile(0.99, sum(rate(gaamingblog_http_request_duration_seconds_bucket{cluster=\"cluster1\"}[5m])) by (le))",
            "legendFormat": "P99 - 集群1"
          }
        ],
        "yaxes": [
          {"format": "s", "label": "时间"}
        ]
      },
      {
        "title": "节点资源使用率 - 集群1",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
        "targets": [
          {
            "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\",cluster=\"cluster1\"}[5m])) * 100)",
            "legendFormat": "{{instance}} - CPU"
          },
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes{cluster=\"cluster1\"} / node_memory_MemTotal_bytes{cluster=\"cluster1\"})) * 100",
            "legendFormat": "{{instance}} - 内存"
          }
        ],
        "yaxes": [
          {"format": "percent", "label": "使用率 %", "max": 100}
        ]
      },
      {
        "title": "节点资源使用率 - 集群2",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
        "targets": [
          {
            "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\",cluster=\"cluster2\"}[5m])) * 100)",
            "legendFormat": "{{instance}} - CPU"
          },
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes{cluster=\"cluster2\"} / node_memory_MemTotal_bytes{cluster=\"cluster2\"})) * 100",
            "legendFormat": "{{instance}} - 内存"
          }
        ],
        "yaxes": [
          {"format": "percent", "label": "使用率 %", "max": 100}
        ]
      },
      {
        "title": "Pod状态 - 集群1",
        "type": "table",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
        "targets": [
          {
            "expr": "kube_pod_status_phase{cluster=\"cluster1\",namespace=\"default\"}",
            "format": "table",
            "instant": true
          }
        ],
        "transformations": [
          {
            "id": "organize",
            "options": {
              "excludeByName": {"Time": true, "__name__": true, "job": true},
              "indexByName": {"pod": 0, "phase": 1, "node": 2}
            }
          }
        ]
      },
      {
        "title": "Pod状态 - 集群2",
        "type": "table",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 20},
        "targets": [
          {
            "expr": "kube_pod_status_phase{cluster=\"cluster2\",namespace=\"default\"}",
            "format": "table",
            "instant": true
          }
        ]
      },
      {
        "title": "Istio服务网格流量",
        "type": "graph",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 28},
        "targets": [
          {
            "expr": "sum(rate(istio_requests_total{destination_service=~\"gaamingblog.*\"}[5m])) by (source_workload, destination_workload, response_code)",
            "legendFormat": "{{source_workload}} → {{destination_workload}} ({{response_code}})"
          }
        ]
      },
      {
        "title": "数据库连接池状态",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 36},
        "targets": [
          {
            "expr": "gaamingblog_db_connections{state=\"active\"}",
            "legendFormat": "活跃连接 - {{cluster}}"
          },
          {
            "expr": "gaamingblog_db_connections{state=\"idle\"}",
            "legendFormat": "空闲连接 - {{cluster}}"
          }
        ]
      },
      {
        "title": "缓存命中率",
        "type": "piechart",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 36},
        "targets": [
          {
            "expr": "sum(rate(gaamingblog_cache_hits_total{result=\"hit\"}[5m]))",
            "legendFormat": "命中"
          },
          {
            "expr": "sum(rate(gaamingblog_cache_hits_total{result=\"miss\"}[5m]))",
            "legendFormat": "未命中"
          }
        ]
      }
    ]
  }
}
```

#### 8.6.3 多集群节点监控Dashboard

```json
{
  "dashboard": {
    "title": "Kubernetes多集群节点监控",
    "uid": "multicluster-nodes",
    "panels": [
      {
        "title": "所有节点CPU使用率",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "100 - (avg by(instance, cluster) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "{{cluster}} - {{instance}}"
          }
        ]
      },
      {
        "title": "所有节点内存使用率",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "legendFormat": "{{cluster}} - {{instance}}"
          }
        ]
      },
      {
        "title": "磁盘I/O",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "targets": [
          {
            "expr": "rate(node_disk_read_bytes_total[5m])",
            "legendFormat": "{{cluster}} - {{instance}} - 读"
          },
          {
            "expr": "rate(node_disk_written_bytes_total[5m])",
            "legendFormat": "{{cluster}} - {{instance}} - 写"
          }
        ]
      },
      {
        "title": "网络流量",
        "type": "graph",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device!~\"lo|veth.*\"}[5m])",
            "legendFormat": "{{cluster}} - {{instance}} - 接收"
          },
          {
            "expr": "rate(node_network_transmit_bytes_total{device!~\"lo|veth.*\"}[5m])",
            "legendFormat": "{{cluster}} - {{instance}} - 发送"
          }
        ]
      },
      {
        "title": "节点状态表",
        "type": "table",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16},
        "targets": [
          {
            "expr": "kube_node_status_condition{condition=\"Ready\"}",
            "format": "table",
            "instant": true
          }
        ]
      }
    ]
  }
}
```

### 8.7 告警规则配置

#### 8.7.1 GaamingBlog服务告警规则

```yaml
# /etc/prometheus/rules/gaamingblog-alerts.yml
groups:
- name: gaamingblog.rules
  rules:
  # 服务可用性告警
  - alert: GaamingBlogServiceDown
    expr: up{job="gaamingblog"} == 0
    for: 1m
    labels:
      severity: critical
      service: gaamingblog
    annotations:
      summary: "GaamingBlog服务不可用"
      description: "集群 {{ $labels.cluster }} 的GaamingBlog服务已经停止响应超过1分钟"

  # 高错误率告警
  - alert: GaamingBlogHighErrorRate
    expr: |
      sum(rate(gaamingblog_http_requests_total{status=~"5.."}[5m])) by (cluster)
      /
      sum(rate(gaamingblog_http_requests_total[5m])) by (cluster)
      > 0.05
    for: 5m
    labels:
      severity: critical
      service: gaamingblog
    annotations:
      summary: "GaamingBlog高错误率"
      description: "集群 {{ $labels.cluster }} 的错误率超过5%，当前值: {{ $value | humanizePercentage }}"

  # 响应时间告警
  - alert: GaamingBlogHighLatency
    expr: |
      histogram_quantile(0.95, 
        sum(rate(gaamingblog_http_request_duration_seconds_bucket[5m])) by (le, cluster)
      ) > 1
    for: 5m
    labels:
      severity: warning
      service: gaamingblog
    annotations:
      summary: "GaamingBlog响应时间过长"
      description: "集群 {{ $labels.cluster }} 的P95响应时间超过1秒，当前值: {{ $value | humanizeDuration }}"

  # Pod重启告警
  - alert: GaamingBlogPodRestarting
    expr: |
      rate(kube_pod_container_status_restarts_total{container="gaamingblog"}[15m]) * 60 * 15 > 0
    for: 5m
    labels:
      severity: warning
      service: gaamingblog
    annotations:
      summary: "GaamingBlog Pod频繁重启"
      description: "集群 {{ $labels.cluster }} 的Pod {{ $labels.pod }} 在过去15分钟内重启了 {{ $value }} 次"

  # 资源使用率告警
  - alert: GaamingBlogHighCPU
    expr: |
      rate(container_cpu_usage_seconds_total{container="gaamingblog"}[5m]) * 100 > 80
    for: 5m
    labels:
      severity: warning
      service: gaamingblog
    annotations:
      summary: "GaamingBlog CPU使用率过高"
      description: "集群 {{ $labels.cluster }} 的Pod {{ $labels.pod }} CPU使用率超过80%，当前值: {{ $value | humanizePercentage }}"

  # 数据库连接池告警
  - alert: GaamingBlogDBConnectionsExhausted
    expr: |
      gaamingblog_db_connections{state="active"} / gaamingblog_db_connections{state="max"} > 0.9
    for: 5m
    labels:
      severity: critical
      service: gaamingblog
    annotations:
      summary: "GaamingBlog数据库连接池即将耗尽"
      description: "集群 {{ $labels.cluster }} 的数据库连接池使用率超过90%"

  # 缓存命中率告警
  - alert: GaamingBlogLowCacheHitRate
    expr: |
      sum(rate(gaamingblog_cache_hits_total{result="hit"}[5m])) 
      / 
      sum(rate(gaamingblog_cache_hits_total[5m])) 
      < 0.5
    for: 10m
    labels:
      severity: warning
      service: gaamingblog
    annotations:
      summary: "GaamingBlog缓存命中率过低"
      description: "集群 {{ $labels.cluster }} 的缓存命中率低于50%，当前值: {{ $value | humanizePercentage }}"

  # 金丝雀发布监控
  - alert: GaamingBlogCanaryHighErrorRate
    expr: |
      sum(rate(gaamingblog_http_requests_total{status=~"5..",version="canary"}[5m])) 
      / 
      sum(rate(gaamingblog_http_requests_total{version="canary"}[5m]))
      > 0.02
    for: 2m
    labels:
      severity: critical
      service: gaamingblog
      release: canary
    annotations:
      summary: "金丝雀版本错误率过高"
      description: "金丝雀版本错误率超过2%，建议立即回滚"

- name: node.rules
  rules:
  # 节点CPU告警
  - alert: NodeHighCPU
    expr: |
      100 - (avg by(instance, cluster) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "节点CPU使用率过高"
      description: "集群 {{ $labels.cluster }} 的节点 {{ $labels.instance }} CPU使用率超过85%"

  # 节点内存告警
  - alert: NodeHighMemory
    expr: |
      (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "节点内存使用率过高"
      description: "集群 {{ $labels.cluster }} 的节点 {{ $labels.instance }} 内存使用率超过85%"

  # 节点磁盘告警
  - alert: NodeDiskSpaceLow
    expr: |
      (node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}) * 100 < 15
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "节点磁盘空间不足"
      description: "集群 {{ $labels.cluster }} 的节点 {{ $labels.instance }} 磁盘使用率超过85%"

  # 节点不可达告警
  - alert: NodeDown
    expr: up{job="node-exporter"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "节点不可达"
      description: "集群 {{ $labels.cluster }} 的节点 {{ $labels.instance }} 已经不可达超过1分钟"

- name: kubernetes.rules
  rules:
  # 集群API Server告警
  - alert: KubernetesAPIServerDown
    expr: up{job="kubernetes-apiservers"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Kubernetes API Server不可用"
      description: "集群 {{ $labels.cluster }} 的API Server已经停止响应"

  # Pod状态告警
  - alert: KubernetesPodNotHealthy
    expr: |
      kube_pod_status_phase{phase=~"Failed|Unknown"} == 1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Pod状态异常"
      description: "集群 {{ $labels.cluster }} 的Pod {{ $labels.pod }} 状态为 {{ $labels.phase }}"

  # Deployment副本数告警
  - alert: KubernetesDeploymentReplicasMismatch
    expr: |
      kube_deployment_spec_replicas != kube_deployment_status_replicas_available
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Deployment副本数不匹配"
      description: "集群 {{ $labels.cluster }} 的Deployment {{ $labels.deployment }} 期望副本数与实际副本数不匹配"
```

### 8.8 AlertManager配置

```yaml
# /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alertmanager@gaaming.com'
  smtp_auth_username: 'alertmanager@gaaming.com'
  smtp_auth_password: 'password'
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

route:
  group_by: ['cluster', 'alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default-receiver'
  routes:
  - match:
      severity: critical
    receiver: 'critical-receiver'
    continue: true
  - match:
      severity: warning
    receiver: 'warning-receiver'
  - match:
      service: gaamingblog
    receiver: 'gaamingblog-team'

receivers:
- name: 'default-receiver'
  slack_configs:
  - channel: '#alerts'
    send_resolved: true
    title: '{{ .Status | toUpper }}: {{ .CommonLabels.alertname }}'
    text: >-
      {{ range .Alerts }}
      *Alert:* {{ .Labels.alertname }}
      *Cluster:* {{ .Labels.cluster }}
      *Severity:* {{ .Labels.severity }}
      *Description:* {{ .Annotations.description }}
      *Details:*
      {{ range .Labels.SortedPairs }} • *{{ .Name }}:* {{ .Value }}
      {{ end }}
      {{ end }}

- name: 'critical-receiver'
  slack_configs:
  - channel: '#critical-alerts'
    send_resolved: true
  email_configs:
  - to: 'oncall@gaaming.com'
    send_resolved: true

- name: 'warning-receiver'
  slack_configs:
  - channel: '#warnings'
    send_resolved: true

- name: 'gaamingblog-team'
  slack_configs:
  - channel: '#gaamingblog-alerts'
    send_resolved: true
  email_configs:
  - to: 'gaamingblog-team@gaaming.com'
    send_resolved: true

inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['cluster', 'alertname']
```

### 8.9 监控系统部署清单

#### 8.9.1 部署步骤

```bash
# 1. 部署Node Exporter到所有节点
ansible-playbook playbook/monitoring/deploy-node-exporter.yml

# 2. 部署kube-state-metrics到两个集群
kubectl apply -f kubernetes-manifests/kube-state-metrics.yaml --context=cluster1
kubectl apply -f kubernetes-manifests/kube-state-metrics.yaml --context=cluster2

# 3. 部署集群Prometheus
ansible-playbook playbook/monitoring/deploy-prometheus-cluster.yml

# 4. 部署中央Prometheus
ansible-playbook playbook/monitoring/deploy-prometheus-central.yml

# 5. 部署AlertManager
ansible-playbook playbook/monitoring/deploy-alertmanager.yml

# 6. 部署Grafana
ansible-playbook playbook/monitoring/deploy-grafana.yml

# 7. 导入Grafana Dashboard
curl -X POST -H "Content-Type: application/json" \
  -d @grafana-dashboards/gaamingblog-dashboard.json \
  http://admin:admin123@192.168.31.60:3000/api/dashboards/db

curl -X POST -H "Content-Type: application/json" \
  -d @grafana-dashboards/multicluster-nodes-dashboard.json \
  http://admin:admin123@192.168.31.60:3000/api/dashboards/db
```

#### 8.9.2 访问监控界面

- **Grafana**: http://192.168.31.60:3000 (admin/admin123)
- **Prometheus中央**: http://192.168.31.80:9090
- **Prometheus集群1**: http://192.168.31.30:9090
- **Prometheus集群2**: http://192.168.31.31:9090
- **AlertManager**: http://192.168.31.81:9093

### 8.10 监控指标清单

#### 8.10.1 基础设施层指标

| 指标名称 | 说明 | 来源 |
|---------|------|------|
| `node_cpu_seconds_total` | CPU使用时间 | Node Exporter |
| `node_memory_MemAvailable_bytes` | 可用内存 | Node Exporter |
| `node_memory_MemTotal_bytes` | 总内存 | Node Exporter |
| `node_filesystem_avail_bytes` | 可用磁盘空间 | Node Exporter |
| `node_network_receive_bytes_total` | 网络接收字节数 | Node Exporter |
| `node_network_transmit_bytes_total` | 网络发送字节数 | Node Exporter |
| `node_load1` | 1分钟负载 | Node Exporter |

#### 8.10.2 Kubernetes层指标

| 指标名称 | 说明 | 来源 |
|---------|------|------|
| `kube_pod_status_phase` | Pod状态 | kube-state-metrics |
| `kube_deployment_status_replicas` | Deployment副本数 | kube-state-metrics |
| `kube_node_status_condition` | 节点状态 | kube-state-metrics |
| `kube_pod_container_status_restarts_total` | 容器重启次数 | kube-state-metrics |
| `kube_pod_container_resource_requests` | 容器资源请求 | kube-state-metrics |

#### 8.10.3 应用层指标

| 指标名称 | 说明 | 来源 |
|---------|------|------|
| `gaamingblog_http_requests_total` | HTTP请求总数 | GaamingBlog应用 |
| `gaamingblog_http_request_duration_seconds` | HTTP请求延迟 | GaamingBlog应用 |
| `gaamingblog_active_connections` | 活跃连接数 | GaamingBlog应用 |
| `gaamingblog_db_connections` | 数据库连接数 | GaamingBlog应用 |
| `gaamingblog_cache_hits_total` | 缓存命中数 | GaamingBlog应用 |

#### 8.10.4 Istio服务网格指标

| 指标名称 | 说明 | 来源 |
|---------|------|------|
| `istio_requests_total` | Istio请求总数 | Istio |
| `istio_request_duration_milliseconds` | Istio请求延迟 | Istio |
| `istio_request_bytes` | Istio请求大小 | Istio |
| `istio_response_bytes` | Istio响应大小 | Istio |

---

## 9. 安全性考虑

### 8.1 网络安全

```yaml
# security/network-policies.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gaamingblog-network-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: gaamingblog
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    - podSelector:
        matchLabels:
          app: istio-ingressgateway
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 3306  # MySQL
    - protocol: TCP
      port: 27017  # MongoDB
  - to:
    - namespaceSelector: {}  # 允许DNS查询
    ports:
    - protocol: UDP
      port: 53
```

### 8.2 RBAC配置

```yaml
# security/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gaamingblog-service-account
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gaamingblog-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gaamingblog-role-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: gaamingblog-service-account
  namespace: default
roleRef:
  kind: Role
  name: gaamingblog-role
  apiGroup: rbac.authorization.k8s.io
```

### 8.3 Secret管理

```yaml
# security/sealed-secret.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: gaamingblog-secrets
  namespace: default
spec:
  encryptedData:
    database-password: AgBfj8...  # 使用kubeseal加密
    api-key: AgBfj9...
  template:
    metadata:
      name: gaamingblog-secrets
      namespace: default
    type: Opaque
```

### 8.4 Pod安全策略

```yaml
# security/pod-security-policy.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: gaamingblog-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  readOnlyRootFilesystem: true
```

---

## 9. 实施步骤和最佳实践建议

### 9.1 实施步骤

#### 阶段1：基础设施准备（1-2天）

1. **更新Inventory配置**
   ```bash
   # 更新hosts.ini为多集群架构
   vim inventory/hosts.ini
   ```

2. **创建集群变量文件**
   ```bash
   # 创建集群1变量
   cat > group_vars/cluster1.yml <<EOF
   kubernetes_cluster_name: "cluster1-production"
   kubernetes_pod_network_cidr: "10.244.1.0/16"
   kubernetes_service_cidr: "10.96.1.0/12"
   kube_vip_vip: "192.168.31.100"
   EOF
   
   # 创建集群2变量
   cat > group_vars/cluster2.yml <<EOF
   kubernetes_cluster_name: "cluster2-staging"
   kubernetes_pod_network_cidr: "10.244.2.0/16"
   kubernetes_service_cidr: "10.96.2.0/12"
   kube_vip_vip: "192.168.31.101"
   EOF
   ```

3. **部署Kubernetes集群**
   ```bash
   # 部署集群1
   ansible-playbook playbook/deploy-k8s-cluster.yml -l cluster1
   
   # 部署集群2
   ansible-playbook playbook/deploy-k8s-cluster.yml -l cluster2
   ```

#### 阶段2：核心组件部署（2-3天）

1. **部署Harbor镜像仓库**
   ```bash
   ansible-playbook playbook/harbor/deploy-harbor.yml
   ```

2. **部署Istio服务网格**
   ```bash
   ansible-playbook playbook/istio/deploy-istio.yml
   ```

3. **部署ArgoCD**
   ```bash
   ansible-playbook playbook/argocd/deploy-argocd.yml
   ```

#### 阶段3：CI/CD流水线配置（1-2天）

1. **配置GitLab**
   ```bash
   # 已有GitLab服务器，配置项目仓库
   # 创建GaamingBlog项目仓库
   # 创建GitOps配置仓库
   ```

2. **配置Jenkins**
   ```bash
   # 已有Jenkins服务器，配置Pipeline
   # 安装必要插件：Git, Docker, Kubernetes, ArgoCD
   # 创建Pipeline Job
   ```

3. **配置Webhooks**
   ```bash
   # GitLab -> Jenkins webhook
   # GitLab -> ArgoCD webhook
   ```

#### 阶段4：应用部署和测试（2-3天）

1. **部署GaamingBlog应用**
   ```bash
   # 通过ArgoCD部署应用
   kubectl apply -f infrastructure/argocd/applications/
   ```

2. **配置全局负载均衡**
   ```bash
   # 部署Nginx负载均衡器
   ansible-playbook playbook/nginx/deploy-loadbalancer.yml
   ```

3. **配置DNS**
   ```bash
   # 配置域名解析
   # blog.gaaming.com -> GLB IP
   ```

#### 阶段5：监控和优化（1-2天）

1. **部署监控系统**
   ```bash
   # Prometheus和Grafana已部署
   # 配置监控规则和仪表板
   ```

2. **测试金丝雀发布**
   ```bash
   # 触发Jenkins Pipeline
   # 观察金丝雀发布流程
   ```

3. **性能测试**
   ```bash
   # 进行负载测试
   # 优化配置
   ```

### 9.2 最佳实践建议

#### 9.2.1 配置管理最佳实践

1. **使用Kustomize进行环境差异化配置**
   ```yaml
   # apps/gaamingblog/overlays/production/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   
   resources:
   - ../../base
   
   patchesStrategicMerge:
   - patches/deployment-replicas.yaml
   
   configMapGenerator:
   - name: gaamingblog-config
     behavior: merge
     literals:
     - ENVIRONMENT=production
     - LOG_LEVEL=info
   ```

2. **使用Helm Values进行参数化配置**
   ```yaml
   # 使用不同的values文件
   helm template gaamingblog ./chart \
     -f values.yaml \
     -f values-production.yaml \
     -f values-canary.yaml
   ```

#### 9.2.2 GitOps最佳实践

1. **分支策略**
   - `main`分支：生产环境配置
   - `staging`分支：预发环境配置
   - `feature/*`分支：功能开发
   - 通过PR进行代码审查和合并

2. **自动化同步**
   ```yaml
   # ArgoCD自动同步配置
   syncPolicy:
     automated:
       prune: true
       selfHeal: true
   ```

3. **配置漂移检测**
   ```bash
   # 定期检查配置漂移
   argocd app diff gaamingblog-cluster1
   ```

#### 9.2.3 安全最佳实践

1. **定期更新镜像**
   ```bash
   # 使用Renovate或Dependabot自动更新依赖
   # 定期扫描镜像漏洞
   trivy image registry.cluster1.local/gaamingblog/gaamingblog:latest
   ```

2. **实施最小权限原则**
   ```yaml
   # 只授予必要的权限
   rules:
   - apiGroups: [""]
     resources: ["pods"]
     verbs: ["get", "list"]  # 只读权限
   ```

3. **启用审计日志**
   ```yaml
   # kube-apiserver审计日志配置
   --audit-log-path=/var/log/kubernetes/audit.log
   --audit-log-maxage=30
   --audit-log-maxbackup=10
   --audit-log-maxsize=100
   ```

#### 9.2.4 性能优化最佳实践

1. **资源限制设置**
   ```yaml
   resources:
     limits:
       cpu: "500m"
       memory: "512Mi"
     requests:
       cpu: "250m"
       memory: "256Mi"
   ```

2. **HPA配置**
   ```yaml
   apiVersion: autoscaling/v2
   kind: HorizontalPodAutoscaler
   metadata:
     name: gaamingblog-hpa
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: gaamingblog
     minReplicas: 2
     maxReplicas: 10
     metrics:
     - type: Resource
       resource:
         name: cpu
         target:
           type: Utilization
           averageUtilization: 70
   ```

3. **Pod反亲和性配置**
   ```yaml
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
   ```

#### 9.2.5 监控和告警最佳实践

1. **关键指标监控**
   - 应用层：请求成功率、响应时间、错误率
   - 集群层：节点资源使用率、Pod重启次数
   - 基础设施层：网络延迟、磁盘IO

2. **告警分级**
   - P0（紧急）：服务不可用、数据丢失
   - P1（严重）：性能严重下降、错误率飙升
   - P2（警告）：资源使用率高、接近阈值
   - P3（信息）：配置变更、部署完成

3. **SLO/SLI定义**
   ```yaml
   # SLO定义示例
   - name: availability
     target: 99.9%
     description: 服务可用性不低于99.9%
   
   - name: latency-p99
     target: 200ms
     description: P99延迟不超过200ms
   ```

#### 9.2.6 容灾演练最佳实践

1. **定期演练**
   - 每季度进行一次故障切换演练
   - 每半年进行一次完整的灾难恢复演练
   - 记录演练结果并改进流程

2. **混沌工程**
   ```bash
   # 使用Chaos Mesh进行故障注入
   kubectl apply -f chaos-experiments/pod-kill.yaml
   ```

3. **备份验证**
   ```bash
   # 定期验证备份有效性
   # 每月进行一次备份恢复测试
   ```

---

## 10. 总结

这个Kubernetes多集群架构方案具有以下特点：

### 优势

1. **高可用性**：双集群架构确保服务持续可用
2. **灵活部署**：支持金丝雀发布、蓝绿部署等多种发布策略
3. **自动化运维**：GitOps工作流实现声明式管理
4. **可观测性**：完整的监控、日志、追踪体系
5. **安全性**：多层安全防护机制
6. **可扩展性**：易于扩展新集群和节点

### 技术亮点

1. **多集群服务发现**：使用Istio实现跨集群服务发现和流量管理
2. **全局负载均衡**：通过Nginx/HAProxy实现跨集群负载均衡
3. **GitOps工作流**：ArgoCD实现多集群统一管理
4. **金丝雀发布**：渐进式发布策略降低风险
5. **自动化CI/CD**：Jenkins Pipeline实现端到端自动化

### 成本效益

- 充分利用现有6台虚拟机资源
- 开源技术栈，无许可证成本
- 自动化运维降低人力成本
- 高可用架构减少停机损失

这个方案完全满足您的所有需求，并遵循业界最佳实践。实施过程中可以根据实际情况进行调整和优化。
