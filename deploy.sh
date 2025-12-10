#!/bin/bash
# 快速部署脚本

set -e

echo "====================================="
echo "Kubernetes 高可用集群部署脚本"
echo "====================================="
echo ""

# 切换到 ansible 目录
cd /home/node/ansible

echo "1. 检查 Ansible 安装..."
if ! command -v ansible &> /dev/null; then
    echo "错误: 未安装 Ansible，正在安装..."
    sudo apt update
    sudo apt install -y ansible
fi

ansible --version
echo ""

echo "2. 测试所有节点连接..."
if ansible all -m ping -i inventory/hosts.ini; then
    echo "✓ 所有节点连接成功"
else
    echo "✗ 节点连接失败，请检查 SSH 配置"
    exit 1
fi
echo ""

echo "3. 开始部署 Kubernetes 集群..."
echo "   - 2 个主节点"
echo "   - 4 个工作节点"
echo "   - containerd 运行时"
echo "   - kube-vip 高可用"
echo "   - Calico CNI"
echo ""

read -p "是否继续部署？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "部署已取消"
    exit 0
fi

echo ""
echo "开始部署..."
ansible-playbook playbook/deploy-k8s-cluster.yml

echo ""
echo "====================================="
echo "部署完成！"
echo "====================================="
echo ""
echo "验证命令："
echo "  ssh node@192.168.31.30 'kubectl get nodes -o wide'"
echo "  ssh node@192.168.31.30 'kubectl get pods -A'"
echo "  ssh node@192.168.31.30 'kubectl cluster-info'"
echo ""
echo "高可用 API 端点："
echo "  https://192.168.31.100:6443"
echo ""
