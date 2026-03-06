# Kubernetes多集群直接命令部署指南

## 目录

1. [部署架构](#1-部署架构)
2. [阶段一：所有节点系统准备](#2-阶段一所有节点系统准备)
3. [阶段二：集群1部署](#3-阶段二集群1部署)
4. [阶段三：集群2部署](#4-阶段三集群2部署)
5. [阶段四：基础设施组件部署](#5-阶段四基础设施组件部署)
6. [阶段五：双环境配置](#6-阶段五双环境配置)
7. [阶段六：验证测试](#7-阶段六验证测试)

---

## 1. 部署架构

### 1.1 节点规划

**集群1 (Cluster1)**：
- Master节点：192.168.31.30 (cluster1-master)
- Worker节点：
  - 192.168.31.40 (cluster1-worker1)
  - 192.168.31.41 (cluster1-worker2)
- VIP：192.168.31.100
- Pod CIDR：10.244.1.0/16
- Service CIDR：10.96.1.0/12

**集群2 (Cluster2)**：
- Master节点：192.168.31.31 (cluster2-master)
- Worker节点：
  - 192.168.31.42 (cluster2-worker1)
  - 192.168.31.43 (cluster2-worker2)
- VIP：192.168.31.101
- Pod CIDR：10.244.2.0/16
- Service CIDR：10.96.2.0/12

---

## 2. 阶段一：所有节点系统准备

### 2.1 清理现有集群（所有节点）

**在所有节点执行（192.168.31.30, 31, 40, 41, 42, 43）**：

```bash
# 重置Kubernetes
sudo kubeadm reset -f

# 清理配置文件
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /var/lib/dockershim/
sudo rm -rf /var/lib/etcd/
sudo rm -rf /var/lib/cni/
sudo rm -rf /etc/cni/
sudo rm -rf /root/.kube/config

# 清理iptables
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# 重启containerd
sudo systemctl restart containerd

# 验证清理
ls -la /etc/kubernetes/ 2>/dev/null || echo "清理完成"
```

### 2.2 系统基础配置（所有节点）

**在所有节点执行**：

```bash
# 1. 设置主机名
# 集群1
sudo hostnamectl set-hostname cluster1-master  # 192.168.31.30
sudo hostnamectl set-hostname cluster1-worker1 # 192.168.31.40
sudo hostnamectl set-hostname cluster1-worker2 # 192.168.31.41

# 集群2
sudo hostnamectl set-hostname cluster2-master  # 192.168.31.31
sudo hostnamectl set-hostname cluster2-worker1 # 192.168.31.42
sudo hostnamectl set-hostname cluster2-worker2 # 192.168.31.43

# 2. 配置hosts文件
sudo cat >> /etc/hosts << 'EOF'
# 集群1
192.168.31.30 cluster1-master
192.168.31.40 cluster1-worker1
192.168.31.41 cluster1-worker2

# 集群2
192.168.31.31 cluster2-master
192.168.31.42 cluster2-worker1
192.168.31.43 cluster2-worker2

# VIP
192.168.31.100 cluster1-vip
192.168.31.101 cluster2-vip
EOF

# 3. 关闭swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# 4. 加载必要的内核模块
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 5. 配置内核参数
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# 6. 验证
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

### 2.3 安装containerd（所有节点）

**在所有节点执行**：

```bash
# 1. 安装依赖
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

# 2. 添加Docker官方GPG密钥
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 3. 添加Docker仓库
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. 安装containerd
apt-get update
apt-get install -y containerd.io

# 5. 配置containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 6. 修改SystemdCgroup为true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 7. 重启containerd
systemctl restart containerd
systemctl enable containerd

# 8. 验证
systemctl status containerd
containerd --version
```

### 2.4 安装Kubernetes组件（所有节点）

**在所有节点执行**：

```bash
# 1. 添加Kubernetes仓库
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
  tee /etc/apt/sources.list.d/kubernetes.list

# 2. 安装Kubernetes组件
apt-get update
apt-get install -y kubelet=1.31.3-1.1 kubeadm=1.31.3-1.1 kubectl=1.31.3-1.1

# 3. 锁定版本
apt-mark hold kubelet kubeadm kubectl

# 4. 启用kubelet
systemctl enable kubelet

# 5. 验证
kubeadm version
kubelet --version
kubectl version --client
```

---

## 3. 阶段二：集群1部署

### 3.1 集群1 Master节点初始化（192.168.31.30）

**仅在192.168.31.30执行**：

```bash
# 1. 创建kubeadm配置文件
cat > kubeadm-config-cluster1.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.31.3
controlPlaneEndpoint: "192.168.31.100:6443"
networking:
  podSubnet: "10.244.1.0/16"
  serviceSubnet: "10.96.1.0/12"
clusterName: cluster1
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.31.30
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: cluster1-master
  taints: null
EOF

# 2. 预下载镜像
kubeadm config images pull --config kubeadm-config-cluster1.yaml

# 3. 初始化集群
kubeadm init --config kubeadm-config-cluster1.yaml --upload-certs

# 4. 配置kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 5. 验证集群
kubectl get nodes
kubectl get pods -n kube-system

# 6. 保存join命令（输出中会有，记录下来）
# 例如：
# kubeadm join 192.168.31.100:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### 3.2 安装kube-vip（集群1 Master）

**仅在192.168.31.30执行**：

```bash
# 1. 创建kube-vip RBAC
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-vip
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  name: system:kube-vip-role
rules:
  - apiGroups: [""]
    resources: ["services", "services/status", "nodes"]
    verbs: ["list", "get", "watch", "update"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["list", "get", "watch", "update", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-vip-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-vip-role
subjects:
- kind: ServiceAccount
  name: kube-vip
  namespace: kube-system
EOF

# 2. 创建kube-vip Pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_interface
      value: "ens33"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_ddns
      value: "false"
    - name: svc_enable
      value: "true"
    - name: vip_leaderelection
      value: "true"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: address
      value: "192.168.31.100"
    image: ghcr.io/kube-vip/kube-vip:v0.8.0
    imagePullPolicy: IfNotPresent
    name: kube-vip
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostAliases:
  - hostnames:
    - kubernetes
    ip: 127.0.0.1
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
    name: kubeconfig
status: {}
EOF

# 3. 验证kube-vip
kubectl get pods -n kube-system | grep kube-vip
ip addr show ens33 | grep 192.168.31.100
```

### 3.3 安装Calico网络（集群1 Master）

**仅在192.168.31.30执行**：

```bash
# 1. 下载Calico YAML
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O

# 2. 修改Pod CIDR
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' calico.yaml
sed -i 's|#   value: "192.168.0.0/16"|  value: "10.244.1.0/16"|' calico.yaml

# 3. 安装Calico
kubectl apply -f calico.yaml

# 4. 等待Calico就绪
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s

# 5. 验证网络
kubectl get pods -n kube-system | grep calico
kubectl get nodes
```

### 3.4 集群1 Worker节点加入（192.168.31.40, 192.168.31.41）

**在192.168.31.40和192.168.31.41执行**：

```bash
# 使用Master初始化时输出的join命令
# 例如：
kubeadm join 192.168.31.100:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# 如果没有保存token，在Master节点重新生成：
# kubeadm token create --print-join-command
```

### 3.5 验证集群1（在Master节点）

**在192.168.31.30执行**：

```bash
# 查看节点状态
kubectl get nodes -o wide

# 查看所有Pod
kubectl get pods -A

# 查看组件状态
kubectl get cs

# 测试集群
kubectl run test-nginx --image=nginx --port=80
kubectl expose pod test-nginx --port=80 --target-port=80 --name test-nginx-service
kubectl get svc
kubectl delete pod test-nginx
kubectl delete svc test-nginx-service
```

---

## 4. 阶段三：集群2部署

### 4.1 集群2 Master节点初始化（192.168.31.31）

**仅在192.168.31.31执行**：

```bash
# 1. 创建kubeadm配置文件
cat > kubeadm-config-cluster2.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.31.3
controlPlaneEndpoint: "192.168.31.101:6443"
networking:
  podSubnet: "10.244.2.0/16"
  serviceSubnet: "10.96.2.0/12"
clusterName: cluster2
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.31.31
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: cluster2-master
  taints: null
EOF

# 2. 预下载镜像
kubeadm config images pull --config kubeadm-config-cluster2.yaml

# 3. 初始化集群
kubeadm init --config kubeadm-config-cluster2.yaml --upload-certs

# 4. 配置kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 5. 验证集群
kubectl get nodes
kubectl get pods -n kube-system

# 6. 保存join命令
```

### 4.2 安装kube-vip（集群2 Master）

**仅在192.168.31.31执行**：

```bash
# 1. 创建kube-vip RBAC（同集群1）
kubectl apply -f - <<EOF
[使用集群1相同的RBAC配置]
EOF

# 2. 创建kube-vip Pod（修改VIP地址）
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_interface
      value: "ens33"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_ddns
      value: "false"
    - name: svc_enable
      value: "true"
    - name: vip_leaderelection
      value: "true"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: address
      value: "192.168.31.101"
    image: ghcr.io/kube-vip/kube-vip:v0.8.0
    imagePullPolicy: IfNotPresent
    name: kube-vip
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostAliases:
  - hostnames:
    - kubernetes
    ip: 127.0.0.1
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
    name: kubeconfig
status: {}
EOF

# 3. 验证kube-vip
kubectl get pods -n kube-system | grep kube-vip
ip addr show ens33 | grep 192.168.31.101
```

### 4.3 安装Calico网络（集群2 Master）

**仅在192.168.31.31执行**：

```bash
# 1. 下载Calico YAML
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O

# 2. 修改Pod CIDR
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' calico.yaml
sed -i 's|#   value: "192.168.0.0/16"|  value: "10.244.2.0/16"|' calico.yaml

# 3. 安装Calico
kubectl apply -f calico.yaml

# 4. 等待Calico就绪
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s

# 5. 验证网络
kubectl get pods -n kube-system | grep calico
kubectl get nodes
```

### 4.4 集群2 Worker节点加入（192.168.31.42, 192.168.31.43）

**在192.168.31.42和192.168.31.43执行**：

```bash
# 使用Master初始化时输出的join命令
kubeadm join 192.168.31.101:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### 4.5 验证集群2（在Master节点）

**在192.168.31.31执行**：

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get cs
```

---

## 5. 阶段四：基础设施组件部署

### 5.1 部署Harbor镜像仓库

#### 5.1.1 集群1部署Harbor（192.168.31.30）

**在192.168.31.30执行**：

```bash
# 1. 安装Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 2. 添加Harbor仓库
helm repo add harbor https://helm.goharbor.io
helm repo update

# 3. 创建Namespace
kubectl create namespace harbor

# 4. 部署Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.nodePort.ports.https.nodePort=30003 \
  --set externalURL=https://192.168.31.30:30003 \
  --set harborAdminPassword="Harbor12345" \
  --set persistence.persistentVolumeClaim.registry.size=50Gi \
  --set persistence.persistentVolumeClaim.database.size=10Gi

# 5. 等待就绪
kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=600s

# 6. 验证
kubectl get pods -n harbor
kubectl get svc -n harbor

# 访问：https://192.168.31.30:30003
# 用户名：admin
# 密码：Harbor12345
```

#### 5.1.2 集群2部署Harbor（192.168.31.31）

**在192.168.31.31执行**：

```bash
# 1. 安装Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 2. 添加Harbor仓库
helm repo add harbor https://helm.goharbor.io
helm repo update

# 3. 创建Namespace
kubectl create namespace harbor

# 4. 部署Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.nodePort.ports.https.nodePort=30003 \
  --set externalURL=https://192.168.31.31:30003 \
  --set harborAdminPassword="Harbor12345" \
  --set persistence.persistentVolumeClaim.registry.size=50Gi \
  --set persistence.persistentVolumeClaim.database.size=10Gi

# 5. 等待就绪
kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=600s

# 6. 验证
kubectl get pods -n harbor
```

### 5.2 部署Istio服务网格

#### 5.2.1 集群1部署Istio（192.168.31.30）

**在192.168.31.30执行**：

```bash
# 1. 下载Istio
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 2. 创建Istio配置
cat > istio-cluster1.yaml << 'EOF'
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

# 3. 安装Istio
istioctl install -f istio-cluster1.yaml -y

# 4. 验证
kubectl get pods -n istio-system
kubectl get svc -n istio-system

# 5. 启用自动注入
kubectl label namespace default istio-injection=enabled
```

#### 5.2.2 集群2部署Istio（192.168.31.31）

**在192.168.31.31执行**：

```bash
# 1. 下载Istio（如果还没下载）
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 2. 创建Istio配置
cat > istio-cluster2.yaml << 'EOF'
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

# 3. 安装Istio
istioctl install -f istio-cluster2.yaml -y

# 4. 验证
kubectl get pods -n istio-system
kubectl get svc -n istio-system

# 5. 启用自动注入
kubectl label namespace default istio-injection=enabled
```

### 5.3 部署ArgoCD（集群1）

**在192.168.31.30执行**：

```bash
# 1. 创建Namespace
kubectl create namespace argocd

# 2. 部署ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. 等待就绪
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 4. 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# 5. 端口转发访问
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &

# 访问：https://192.168.31.30:8080
# 用户名：admin
# 密码：上一步获取的密码
```

### 5.4 部署Ingress-Nginx

#### 5.4.1 集群1部署Ingress-Nginx（192.168.31.30）

**在192.168.31.30执行**：

```bash
# 部署Ingress-Nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# 等待就绪
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 验证
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

#### 5.4.2 集群2部署Ingress-Nginx（192.168.31.31）

**在192.168.31.31执行**：

```bash
# 部署Ingress-Nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# 等待就绪
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 验证
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

---

## 6. 阶段五：双环境配置

### 6.1 创建Namespace和资源配额

#### 6.1.1 集群1（192.168.31.30）

**在192.168.31.30执行**：

```bash
# 1. 创建Namespace
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary

# 2. 添加标签
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

# 3. 创建资源配额
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

# 4. 验证
kubectl get namespaces | grep gaamingblog
kubectl get resourcequota -n gaamingblog-prod
kubectl get resourcequota -n gaamingblog-canary
```

#### 6.1.2 集群2（192.168.31.31）

**在192.168.31.31执行**：

```bash
# 执行与集群1相同的命令
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

kubectl apply -f - <<EOF
[使用相同的ResourceQuota配置]
EOF
```

### 6.2 创建Secret

#### 6.2.1 集群1（192.168.31.30）

**在192.168.31.30执行**：

```bash
# 1. 创建数据库Secret - 生产环境
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod

# 2. 创建数据库Secret - 开发环境
kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary

# 3. 创建Harbor Registry Secret - 生产环境
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod

# 4. 创建Harbor Registry Secret - 开发环境
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary

# 5. 验证
kubectl get secret -n gaamingblog-prod
kubectl get secret -n gaamingblog-canary
```

#### 6.2.2 集群2（192.168.31.31）

**在192.168.31.31执行**：

```bash
# 执行与集群1类似的命令，注意修改Harbor地址
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

---

## 7. 阶段六：验证测试

### 7.1 验证集群状态

#### 7.1.1 集群1（192.168.31.30）

**在192.168.31.30执行**：

```bash
# 查看节点
kubectl get nodes -o wide

# 查看所有Pod
kubectl get pods -A

# 查看组件状态
kubectl get cs

# 查看网络
kubectl get pods -n kube-system | grep calico

# 查看Istio
kubectl get pods -n istio-system

# 查看Harbor
kubectl get pods -n harbor

# 查看ArgoCD
kubectl get pods -n argocd

# 查看Ingress
kubectl get svc -n ingress-nginx

# 查看双环境
kubectl get namespaces | grep gaamingblog
kubectl get all -n gaamingblog-prod
kubectl get all -n gaamingblog-canary
```

#### 7.1.2 集群2（192.168.31.31）

**在192.168.31.31执行**：

```bash
# 执行与集群1相同的验证命令
kubectl get nodes -o wide
kubectl get pods -A
kubectl get cs
kubectl get pods -n kube-system | grep calico
kubectl get pods -n istio-system
kubectl get pods -n harbor
kubectl get svc -n ingress-nginx
kubectl get namespaces | grep gaamingblog
kubectl get all -n gaamingblog-prod
kubectl get all -n gaamingblog-canary
```

### 7.2 测试VIP访问

```bash
# 在任意节点测试
curl -k https://192.168.31.100:6443/healthz
curl -k https://192.168.31.101:6443/healthz
```

### 7.3 测试Harbor访问

```bash
# 测试集群1 Harbor
curl -k https://192.168.31.30:30003/api/v2.0/systeminfo

# 测试集群2 Harbor
curl -k https://192.168.31.31:30003/api/v2.0/systeminfo
```

### 7.4 测试ArgoCD访问

```bash
# 端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &

# 访问
curl -k https://192.168.31.30:8080
```

---

## 8. 访问地址汇总

### 8.1 集群1访问地址

- **API Server**: https://192.168.31.100:6443
- **Harbor**: https://192.168.31.30:30003
- **ArgoCD**: https://192.168.31.30:8080

### 8.2 集群2访问地址

- **API Server**: https://192.168.31.101:6443
- **Harbor**: https://192.168.31.31:30003

### 8.3 默认密码

- **Harbor**: admin / Harbor12345
- **ArgoCD**: admin / (使用命令获取)

---

## 9. 故障排查

### 9.1 查看日志

```bash
# 查看kubelet日志
journalctl -u kubelet -f

# 查看containerd日志
journalctl -u containerd -f

# 查看Pod日志
kubectl logs -n <namespace> <pod-name>

# 查看事件
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### 9.2 重置集群

```bash
# 在所有节点执行
kubeadm reset -f
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/etcd/
rm -rf /var/lib/cni/
rm -rf /etc/cni/
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
systemctl restart containerd
```

---

## 10. 总结

### 10.1 部署时间估算

- **阶段一：系统准备**：30分钟
- **阶段二：集群1部署**：1小时
- **阶段三：集群2部署**：1小时
- **阶段四：基础设施组件**：2小时
- **阶段五：双环境配置**：30分钟
- **阶段六：验证测试**：30分钟
- **总计**：约5-6小时

### 10.2 关键命令总结

1. **集群初始化**：`kubeadm init --config kubeadm-config.yaml`
2. **Worker加入**：`kubeadm join <vip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>`
3. **安装网络**：`kubectl apply -f calico.yaml`
4. **安装Istio**：`istioctl install -f istio-config.yaml`
5. **安装Harbor**：`helm install harbor harbor/harbor`
6. **安装ArgoCD**：`kubectl apply -n argocd -f install.yaml`

### 10.3 下一步

1. 配置GitOps仓库
2. 创建应用Helm Chart
3. 配置ArgoCD Applications
4. 部署GaamingBlog应用
5. 配置CI/CD流水线
6. 配置监控和告警
