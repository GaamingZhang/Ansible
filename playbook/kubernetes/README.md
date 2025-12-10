# Kubernetes 高可用集群部署

使用 Ansible 自动化部署 Kubernetes 高可用集群，包含 2 个主节点和 4 个工作节点。

## 功能特性

- Kubernetes v1.31.3
- 高可用架构（2 主节点 + kube-vip）
- containerd 容器运行时
- Calico CNI v3.29.1
- kube-vip v0.8.7（VIP 高可用）
- 自动配置 kubeconfig
- 系统优化配置

## 集群架构

### 主节点（Master Nodes）
- **KubernetesMaster000**: 192.168.31.30
- **KubernetesMaster001**: 192.168.31.31

### 工作节点（Worker Nodes）
- **KubernetesWorker000**: 192.168.31.40
- **KubernetesWorker001**: 192.168.31.41
- **KubernetesWorker002**: 192.168.31.42
- **KubernetesWorker003**: 192.168.31.43

### 高可用配置
- **VIP**: 192.168.31.100 (kube-vip)
- **API Server**: https://192.168.31.100:6443

## 前置要求

1. 6 台 Ubuntu 24.04 虚拟机
2. 每台至少 2 CPU, 4GB RAM
3. 至少 20GB 磁盘空间
4. 所有节点时间同步
5. 所有节点可访问互联网（通过代理 192.168.31.132:20171）
6. Ansible 控制节点已配置 SSH 免密登录

## 网络规划

- **Pod 网络**: 10.244.0.0/16
- **Service 网络**: 10.96.0.0/12
- **节点网络**: 192.168.31.0/24

## 部署步骤

### 1. 配置 inventory

检查 `/home/node/ansible/inventory/hosts.ini`:

```ini
[kubernetes_masters]
KubernetesMaster000 ansible_host=192.168.31.30
KubernetesMaster001 ansible_host=192.168.31.31

[kubernetes_workers]
KubernetesWorker000 ansible_host=192.168.31.40
KubernetesWorker001 ansible_host=192.168.31.41
KubernetesWorker002 ansible_host=192.168.31.42
KubernetesWorker003 ansible_host=192.168.31.43

[kubernetes_first_master]
KubernetesMaster000 ansible_host=192.168.31.30

[kubernetes_cluster:children]
kubernetes_masters
kubernetes_workers
```

### 2. 执行部署

```bash
cd /home/node/ansible
ansible-playbook playbook/deploy-k8s-cluster.yml
```

部署过程包括：
1. 系统准备（禁用 swap、配置内核参数）
2. 安装 containerd
3. 安装 Kubernetes 组件
4. 初始化第一个主节点
5. 部署 Calico CNI
6. 部署 kube-vip（高可用 VIP）
7. 加入其他主节点
8. 加入工作节点

### 3. 分步执行（可选）

```bash
# 仅系统准备
ansible-playbook playbook/deploy-k8s-cluster.yml --tags system-prepare

# 仅安装 containerd
ansible-playbook playbook/deploy-k8s-cluster.yml --tags containerd

# 仅安装 Kubernetes
ansible-playbook playbook/deploy-k8s-cluster.yml --tags kubernetes
```

## 验证部署

### 查看节点状态

```bash
# 从控制节点查看
ansible kubernetes_first_master -i inventory/hosts.ini -m shell -a "kubectl get nodes -o wide"

# 或登录主节点
ssh node@192.168.31.30
kubectl get nodes -o wide
```

预期输出：
```
NAME                   STATUS   ROLES           AGE   VERSION
kubernetesmaster000    Ready    control-plane   10m   v1.31.3
kubernetesmaster001    Ready    control-plane   8m    v1.31.3
kubernetesworker000    Ready    <none>          5m    v1.31.3
kubernetesworker001    Ready    <none>          5m    v1.31.3
kubernetesworker002    Ready    <none>          5m    v1.31.3
kubernetesworker003    Ready    <none>          5m    v1.31.3
```

### 查看系统 Pod

```bash
kubectl get pods -A
```

预期看到：
- kube-system: kube-apiserver, kube-controller-manager, kube-scheduler, etcd
- kube-system: calico-node (CNI)
- kube-system: kube-vip (高可用 VIP)
- kube-system: coredns

### 验证高可用 VIP

```bash
# 测试 VIP 连通性
ping 192.168.31.100

# 测试 API Server
curl -k https://192.168.31.100:6443/healthz

# 查看 kube-vip 状态
kubectl get pods -n kube-system | grep kube-vip
```

### 验证集群功能

```bash
# 创建测试 Deployment
kubectl create deployment nginx --image=nginx --replicas=3

# 查看 Pod
kubectl get pods -o wide

# 暴露服务
kubectl expose deployment nginx --port=80 --type=NodePort

# 查看服务
kubectl get svc nginx

# 清理测试
kubectl delete deployment nginx
kubectl delete svc nginx
```

## 配置 kubectl（远程访问）

### 从控制节点访问

```bash
# 复制 kubeconfig
mkdir -p ~/.kube
scp node@192.168.31.30:/etc/kubernetes/admin.conf ~/.kube/config

# 测试连接
kubectl get nodes
```

### 从本地机器访问

1. 复制 kubeconfig 到本地：
```bash
scp node@192.168.31.30:/etc/kubernetes/admin.conf ~/.kube/config
```

2. 修改 server 地址为 VIP：
```bash
kubectl config set-cluster kubernetes --server=https://192.168.31.100:6443
```

3. 测试连接：
```bash
kubectl get nodes
```

## 集群管理

### 添加工作节点

1. 准备新节点（安装操作系统、配置网络）

2. 添加到 inventory:
```ini
[kubernetes_workers]
...
KubernetesWorker004 ansible_host=192.168.31.44
```

3. 获取 join 命令：
```bash
ssh node@192.168.31.30
kubeadm token create --print-join-command
```

4. 在新节点上执行 join 命令

### 删除节点

```bash
# 驱逐 Pod
kubectl drain kubernetesworker003 --delete-emptydir-data --ignore-daemonsets

# 删除节点
kubectl delete node kubernetesworker003

# 在被删除的节点上重置
ssh node@192.168.31.43
sudo kubeadm reset -f
```

### 升级集群

查看升级计划：
```bash
sudo kubeadm upgrade plan
```

升级控制平面：
```bash
# 在第一个主节点
sudo kubeadm upgrade apply v1.32.0

# 在其他主节点
sudo kubeadm upgrade node
```

升级 kubelet：
```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get update
sudo apt-get install -y kubelet=1.32.0-1.1 kubectl=1.32.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

## 网络配置

### Calico CNI

Calico 配置文件位于主节点，查看状态：
```bash
kubectl get pods -n kube-system | grep calico

# 查看 Calico 版本
kubectl get clusterinformation default -o yaml
```

### 网络策略示例

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

## 存储配置

### 本地存储（hostPath）

示例 PV:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data
```

### 动态存储（推荐使用 NFS 或 Ceph）

安装 NFS provisioner:
```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=192.168.31.200 \
  --set nfs.path=/exports
```

## 监控和日志

### 部署 Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

查看资源使用：
```bash
kubectl top nodes
kubectl top pods -A
```

### 查看日志

```bash
# Pod 日志
kubectl logs <pod-name>

# 系统组件日志
journalctl -u kubelet -f

# API Server 日志
kubectl logs -n kube-system kube-apiserver-kubernetesmaster000
```

## 备份和恢复

### 备份 etcd

```bash
# 在主节点上
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

### 恢复 etcd

```bash
# 停止 API Server
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# 恢复 snapshot
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restore

# 替换数据目录
sudo mv /var/lib/etcd /var/lib/etcd.backup
sudo mv /var/lib/etcd-restore /var/lib/etcd

# 启动 API Server
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
```

## 故障排查

### 节点 NotReady

```bash
# 查看节点详情
kubectl describe node <node-name>

# 检查 kubelet 日志
ssh node@<node-ip>
sudo journalctl -u kubelet -f
```

### Pod 启动失败

```bash
# 查看 Pod 事件
kubectl describe pod <pod-name>

# 查看容器日志
kubectl logs <pod-name> -c <container-name>

# 检查镜像拉取
kubectl get events --sort-by='.lastTimestamp'
```

### 网络问题

```bash
# 测试 Pod 间网络
kubectl run test-pod --image=busybox --rm -it -- sh
ping <another-pod-ip>

# 检查 Calico
kubectl get pods -n kube-system | grep calico
kubectl logs -n kube-system <calico-pod>
```

## 安全加固

### RBAC 配置

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

### Pod Security Policies

```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  runAsUser:
    rule: MustRunAsNonRoot
```

## 常见问题

### kube-vip VIP 不可用
1. 检查网络接口名称是否正确
2. 确保 VIP 未被其他设备占用
3. 查看 kube-vip pod 日志

### Pod 无法调度
1. 检查节点资源是否充足：`kubectl top nodes`
2. 查看 Pod 事件：`kubectl describe pod <pod-name>`
3. 检查 taints 和 tolerations

### 集群证书过期
```bash
# 检查证书有效期
kubeadm certs check-expiration

# 续期证书
kubeadm certs renew all
```

## 卸载集群

```bash
# 在所有节点上
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd
sudo rm -rf ~/.kube

# 清理 iptables
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# 卸载软件包
sudo apt remove -y kubelet kubeadm kubectl containerd
sudo apt autoremove -y
```

## 参考资料

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Calico 文档](https://docs.projectcalico.org/)
- [kube-vip 文档](https://kube-vip.io/)
- [containerd 文档](https://containerd.io/)
