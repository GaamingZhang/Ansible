# Kubernetes多集群直接部署命令清单

## 快速部署命令（按顺序执行）

### 1. 所有节点系统准备

#### 1.1 清理现有集群（所有节点：30, 31, 40, 41, 42, 43）

```bash
# 在所有节点执行
kubeadm reset -f
rm -rf /etc/kubernetes/ /var/lib/kubelet/ /var/lib/dockershim/ /var/lib/etcd/ /var/lib/cni/ /etc/cni/ /root/.kube/config
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
systemctl restart containerd
```

#### 1.2 设置主机名（每个节点单独执行）

```bash
# 192.168.31.30
hostnamectl set-hostname cluster1-master

# 192.168.31.31
hostnamectl set-hostname cluster2-master

# 192.168.31.40
hostnamectl set-hostname cluster1-worker1

# 192.168.31.41
hostnamectl set-hostname cluster1-worker2

# 192.168.31.42
hostnamectl set-hostname cluster2-worker1

# 192.168.31.43
hostnamectl set-hostname cluster2-worker2
```

#### 1.3 配置hosts（所有节点）

```bash
cat >> /etc/hosts << 'EOF'
# 集群1
192.168.31.30 cluster1-master
192.168.31.40 cluster1-worker1
192.168.31.41 cluster1-worker2
192.168.31.100 cluster1-vip

# 集群2
192.168.31.31 cluster2-master
192.168.31.42 cluster2-worker1
192.168.31.43 cluster2-worker2
192.168.31.101 cluster2-vip
EOF
```

#### 1.4 系统基础配置（所有节点）

```bash
# 关闭swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# 加载内核模块
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 配置内核参数
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

#### 1.5 安装containerd（所有节点）

```bash
# 安装依赖
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

# 添加Docker仓库
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装containerd
apt-get update
apt-get install -y containerd.io

# 配置containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 重启containerd
systemctl restart containerd
systemctl enable containerd
```

#### 1.6 安装Kubernetes组件（所有节点）

```bash
# 添加Kubernetes仓库
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# 安装Kubernetes
apt-get update
apt-get install -y kubelet=1.31.3-1.1 kubeadm=1.31.3-1.1 kubectl=1.31.3-1.1
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
```

---

### 2. 集群1部署（192.168.31.30）

#### 2.1 初始化集群1 Master（仅在192.168.31.30执行）

```bash
# 创建配置文件
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

# 预下载镜像
kubeadm config images pull --config kubeadm-config-cluster1.yaml

# 初始化集群
kubeadm init --config kubeadm-config-cluster1.yaml --upload-certs

# 配置kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 验证
kubectl get nodes
```

#### 2.2 安装kube-vip（仅在192.168.31.30执行）

```bash
# 创建RBAC
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

# 创建kube-vip Pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
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
    - name: address
      value: "192.168.31.100"
    image: ghcr.io/kube-vip/kube-vip:v0.8.0
    name: kube-vip
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
    name: kubeconfig
EOF

# 验证
kubectl get pods -n kube-system | grep kube-vip
```

#### 2.3 安装Calico网络（仅在192.168.31.30执行）

```bash
# 下载Calico
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O

# 修改Pod CIDR
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' calico.yaml
sed -i 's|#   value: "192.168.0.0/16"|  value: "10.244.1.0/16"|' calico.yaml

# 安装Calico
kubectl apply -f calico.yaml

# 等待就绪
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s

# 验证
kubectl get nodes
```

#### 2.4 Worker节点加入集群1（在192.168.31.40和192.168.31.41执行）

```bash
# 在Master节点获取join命令
kubeadm token create --print-join-command

# 在Worker节点执行输出的join命令
# 例如：
kubeadm join 192.168.31.100:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

---

### 3. 集群2部署（192.168.31.31）

#### 3.1 初始化集群2 Master（仅在192.168.31.31执行）

```bash
# 创建配置文件
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

# 预下载镜像
kubeadm config images pull --config kubeadm-config-cluster2.yaml

# 初始化集群
kubeadm init --config kubeadm-config-cluster2.yaml --upload-certs

# 配置kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 验证
kubectl get nodes
```

#### 3.2 安装kube-vip（仅在192.168.31.31执行）

```bash
# 创建RBAC（同集群1）
kubectl apply -f - <<EOF
[使用集群1相同的RBAC配置]
EOF

# 创建kube-vip Pod（修改VIP）
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
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
    - name: address
      value: "192.168.31.101"
    image: ghcr.io/kube-vip/kube-vip:v0.8.0
    name: kube-vip
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/admin.conf
    name: kubeconfig
EOF
```

#### 3.3 安装Calico网络（仅在192.168.31.31执行）

```bash
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' calico.yaml
sed -i 's|#   value: "192.168.0.0/16"|  value: "10.244.2.0/16"|' calico.yaml
kubectl apply -f calico.yaml
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
```

#### 3.4 Worker节点加入集群2（在192.168.31.42和192.168.31.43执行）

```bash
# 在Master节点获取join命令
kubeadm token create --print-join-command

# 在Worker节点执行
kubeadm join 192.168.31.101:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

---

### 4. 基础设施组件部署

#### 4.1 部署Harbor（集群1：192.168.31.30）

```bash
# 安装Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 部署Harbor
helm repo add harbor https://helm.goharbor.io
helm repo update
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
```

#### 4.2 部署Harbor（集群2：192.168.31.31）

```bash
# 安装Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 部署Harbor
helm repo add harbor https://helm.goharbor.io
helm repo update
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

#### 4.3 部署Istio（集群1：192.168.31.30）

```bash
# 下载Istio
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 安装Istio
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
EOF

istioctl install -f istio-cluster1.yaml -y
kubectl get pods -n istio-system
```

#### 4.4 部署Istio（集群2：192.168.31.31）

```bash
# 下载Istio
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 安装Istio
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
EOF

istioctl install -f istio-cluster2.yaml -y
kubectl get pods -n istio-system
```

#### 4.5 部署ArgoCD（集群1：192.168.31.30）

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 获取密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# 端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &
```

#### 4.6 部署Ingress-Nginx（集群1和集群2）

```bash
# 集群1（192.168.31.30）
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# 集群2（192.168.31.31）
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

---

### 5. 双环境配置

#### 5.1 创建Namespace（集群1和集群2）

```bash
# 集群1（192.168.31.30）
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled

# 集群2（192.168.31.31）
kubectl create namespace gaamingblog-prod
kubectl create namespace gaamingblog-canary
kubectl label namespace gaamingblog-prod environment=production istio-injection=enabled
kubectl label namespace gaamingblog-canary environment=canary istio-injection=enabled
```

#### 5.2 创建Secret（集群1：192.168.31.30）

```bash
# 数据库Secret - 生产环境
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod

# 数据库Secret - 开发环境
kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary

# Harbor Registry Secret - 生产环境
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod

# Harbor Registry Secret - 开发环境
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.30:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary
```

#### 5.3 创建Secret（集群2：192.168.31.31）

```bash
# 数据库Secret - 生产环境
kubectl create secret generic gaamingblog-prod-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_prod \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-prod

# 数据库Secret - 开发环境
kubectl create secret generic gaamingblog-canary-db-secret \
  --from-literal=db-host=mysql-service.default.svc.cluster.local \
  --from-literal=db-port=3306 \
  --from-literal=db-name=gaamingblog_canary \
  --from-literal=db-user=gaamingblog \
  --from-literal=db-password='GaamingBlog@2024#Prod' \
  --namespace=gaamingblog-canary

# Harbor Registry Secret - 生产环境
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.31:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-prod

# Harbor Registry Secret - 开发环境
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=192.168.31.31:30003 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=gaamingblog-canary
```

---

### 6. 验证部署

#### 6.1 验证集群1（192.168.31.30）

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get namespaces | grep gaamingblog
```

#### 6.2 验证集群2（192.168.31.31）

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get namespaces | grep gaamingblog
```

---

### 7. 访问地址

- **集群1 API**: https://192.168.31.100:6443
- **集群2 API**: https://192.168.31.101:6443
- **Harbor集群1**: https://192.168.31.30:30003 (admin/Harbor12345)
- **Harbor集群2**: https://192.168.31.31:30003 (admin/Harbor12345)
- **ArgoCD**: https://192.168.31.30:8080 (admin/获取的密码)

---

### 8. 预计时间

- **系统准备**：30分钟
- **集群1部署**：1小时
- **集群2部署**：1小时
- **基础设施组件**：2小时
- **双环境配置**：30分钟
- **总计**：约5小时
