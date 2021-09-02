# File Name: init_installk8s.sh
# Author: 老张
# mail: as953027255@qq.com
# http://1717zgy.com/
# Created Time: Thu 31 Dec 2020 09:30:52 PM CST
#!/bin/bash

# 修改网卡名
IP=`ip a |grep eth0 | sed -rn "2s/[^0-9]*([0-9.]+).*/\1/p"`
PI(){
grep lv=centos /etc/default/grub
if [ $? = 0 ];then
	NAT=`sed -ri 's/^(GRUB_CMDLINE_LINUX=\"crashkernel=auto ) .* (rhgb quiet)/\1\2 net.ifnames=0 biosdevname=0/g' /etc/default/grub`
fi
}

# 静态IP
IP(){
	
	 cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
BOOTPROTO=static                                                                    
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=$IP
GATEWAY=10.0.0.2
PREFIX=24
DNS1=114.114.114.114
DNS2=8.8.8.8
EOF
	systemctl restart network
}

# 阿里源
YUM(){
	mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
	curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
	yum clean all
	yum makecache

}

# 常用命令下载
CMD(){

	yum install -y wget vim glances atop ncdu iotop iftop nethogs \
		git lrzsz bash-completion gcc gcc-c++ autoconf automake make \
         zlib zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel libffi libffi-devel xz xz-devel	
}

# 修改主机命令提示
PS(){

cat > /etc/profile.d/env.sh << EOF
PS1="\[\e[1;32m\][\[\e[0m\]\t \[\e[1;33m\]\u\[\e[36m\]@\h\[\e[1;31m\] \W\[\e[1;32m\]]\[\e[0m\]\\\\$"
HISTTIMEFORMAT="%F %T"
HISTCONTROL=ignoreboth
EOF
}

# 调整时间
TIME(){
read -p "please input hostname: " name
hostnamectl set-hostname $name

timedatectl set-timezone Asia/Shanghai
timedatectl set-local-rtc 0
systemctl restart rsyslog

}

# 禁用 swap
SWAP(){
swapoff -a && sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}


# 调整内核参数针对 K8S
K8S_conf(){

	cat > /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-iptables=1    #开启网桥模式
net.bridge.bridge-nf-call-ip6tables=1   #开启网桥模式
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启 OOM  
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1    #关闭IPV6的协议
net.netfilter.nf_conntrack_max=2310720
EOF

sysctl -p /etc/sysctl.d/kubernetes.conf 
}

# 关闭防火墙selinux
SELinux(){

	systemctl stop firewalld && systemctl disable firewalld
	sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
	setenforce 0

}

# 安装 docker
install_docker(){

yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
yum install -y docker-ce-18.06.3.ce-3.el7

Conf=/etc/docker
if [ -d ${Conf} ];then
cat > /etc/docker/daemon.json << EOF
{
   "registry-mirrors": ["https://hpqoo1ip.mirror.aliyuncs.com"]
}
EOF

else
mkdir -p ${Conf} && cat > /etc/docker/daemon.json << EOF
{
   "registry-mirrors": ["https://hpqoo1ip.mirror.aliyuncs.com"]
}
EOF
fi
systemctl daemon-reload 
systemctl enable --now docker
}

# 安装 k8s
k8s_install(){
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF


cat << EOF
1.k8s-1.15.5
2.K8s-1.18.6
3.K8s-1.20.1
4.exit
EOF

read -p "请输入需要安装的 K8s 版本！" V
	case $V in
1 )
	yum install  kubeadm-1.15.5-0 kubelet-1.15.5-0 kubectl-1.15.5-0 -y 

	systemctl enable kubelet && systemctl start kubelet


	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.15.5
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.15.5
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.15.5
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.15.5
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.1
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.3.10
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:1.3.1

	kubeadm init --apiserver-advertise-address=$IP  --apiserver-bind-port=6443 --kubernetes-version=v1.15.5 --pod-network-cidr=10.233.0.0/16 --service-cidr=172.30.0.0/16 --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers --ignore-preflight-errors=swap
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config 
    echo 'source <(kubectl completion bash)' >> ~/.bashrc

	;;

2 )	
	yum install  kubeadm-1.18.6 kubelet-1.18.6 kubectl-1.18.6 -y
    systemctl enable kubelet && systemctl start kubelet
  
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.18.6
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.18.6
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.18.6
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.18.6
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.2
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.4.3-0
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:1.6.7

	kubeadm init --apiserver-advertise-address=$IP  --apiserver-bind-port=6443 --kubernetes-version=v1.18.6 --pod-network-cidr=10.233.0.0/16 --service-cidr=172.30.0.0/16 --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers --ignore-preflight-errors=swap

	 mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    echo 'source <(kubectl completion bash)' >> ~/.bashrc

    ;;

3 )
	yum install  kubeadm-1.20.1 kubelet-1.20.1 kubectl-1.20.1 -y

    systemctl enable kubelet && systemctl start kubelet

	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.20.1
	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.20.1
	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.20.1
	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.20.1
	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.2
	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.4.13-0
	docker image pull registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:1.7.0

	kubeadm init --apiserver-advertise-address=$IP  --apiserver-bind-port=6443 --kubernetes-version=v1.20.1 --pod-network-cidr=10.233.0.0/16 --service-cidr=172.30.0.0/16 --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers --ignore-preflight-errors=swap

	mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    ;;

* )
	echo "请输入正确的 K8S 版本"
esac


}

# 安装网络插件
install_CNI() {
  curl https://docs.projectcalico.org/v3.9/manifests/calico-etcd.yaml -O  && echo "calico文件下载完成"
  POD_CIDR=`grep 'cluster-cidr' /etc/kubernetes/manifests/kube-controller-manager.yaml | awk -F= '{print $2}'`
 
  sed '/CALICO_IPV4POOL_CIDR/{n;s#".*"#"'$POD_CIDR'"#}' calico-etcd.yaml -i

  sed -i 's/# \(etcd-.*\)/\1/' calico-etcd.yaml
  etcd_key=$(cat /etc/kubernetes/pki/etcd/peer.key | base64 -w 0)
  etcd_crt=$(cat /etc/kubernetes/pki/etcd/peer.crt | base64 -w 0)
  etcd_ca=$(cat /etc/kubernetes/pki/etcd/ca.crt | base64 -w 0)
  sed -i -e 's/\(etcd-key: \).*/\1'$etcd_key'/' \
     -e 's/\(etcd-cert: \).*/\1'$etcd_crt'/' \
     -e 's/\(etcd-ca: \).*/\1'$etcd_ca'/' calico-etcd.yaml

  ETCD=$(grep 'advertise-client-urls' /etc/kubernetes/manifests/etcd.yaml | awk -F= '{print $2}')
  sed -i -e 's@\(etcd_endpoints: \).*@\1'$ETCD'@' \
     -e 's/\(etcd_.*:\).*#/\1/' \
     -e 's/replicas: 1/replicas: 2/' calico-etcd.yaml

   sed '/autodetect/a\            - name: IP_AUTODETECTION_METHOD\n              value: "interface=eth0"' -i calico-etcd.yaml  && \
	kubectl apply -f calico-etcd.yaml && \
	echo "***********\nCNI 已安装"
}

# node 节点安装
k8sNode(){
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

  yum install  kubeadm-1.15.5-0 kubelet-1.15.5-0 -y

docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.15.5
docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.15.5
docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.15.5
docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.15.5
docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.1
docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.3.10
docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:1.3.1

systemctl enable kubelet && systemctl start kubelet

}


# PI
# IP
# YUM
# CMD
# PS
# TIME
SWAP
K8S_conf
SELinux
install_docker

# node 节点注释下面两个函数
k8s_install
install_CNI

# master 节点注释下面这个函数
#k8sNode