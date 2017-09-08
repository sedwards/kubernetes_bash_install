#!/bin/sh


install_common (){
  ###
  ### Setup Repo ###
  ###
cat << EOF > /etc/yum.repos.d/virt7-docker-common-release.repo
[virt7-docker-common-release]
name=virt7-docker-common-release
baseurl=http://cbs.centos.org/repos/virt7-docker-common-release/x86_64/os/
gpgcheck=0
EOF

  ###
  ### Install Packages ###
  ###
  yum -y install --enablerepo=virt7-docker-common-release kubernetes etcd flannel

  ### Setup Kube Config ###
  ### FIXME: Variables
cat << EOF > /etc/kubernetes/config

# Comma separated list of nodes running etcd cluster
KUBE_ETCD_SERVERS="--etcd-servers=http://172.16.0.1:2379"
# Logging will be stored in system journal
KUBE_LOGTOSTDERR="--logtostderr=true"
# Journal message level, 0 is debug
KUBE_LOG_LEVEL="--v=0"
# Should this cluster be allowed to run privileged docker containers
KUBE_ALLOW_PRIV="--allow-privileged=false"
# Api-server endpoint used in scheduler and controller-manager
KUBE_MASTER="--master=http://172.16.0.1:8080"
EOF
}

remove_common(){
  yum remove -y kubernetes etcd flannel 
  rm /etc/kubernetes/config
  rm /etc/yum.repos.d/virt7-docker-common-release.repo 
}

setup_etcd_master (){

  ### Setup etcd ###
  ###
cat > /etc/etcd/etcd.conf   <<EOF
#[member]
ETCD_NAME=default
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"

ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
#[cluster]
ETCD_ADVERTISE_CLIENT_URLS="http://0.0.0.0:2379"
EOF

  ### Generate CA Cert 
  ### FIXME: Variables
  bash make-ca-cert.sh "172.16.0.1" "IP:172.16.0.1,IP:10.254.0.1,DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local"

  ### apiserver configuration
  ### 
cat > /etc/kubernetes/apiserver << EOF
# Bind kube API server to this IP
KUBE_API_ADDRESS="--address=0.0.0.0"
# Port that kube api server listens to.
KUBE_API_PORT="--port=8080"
# Port kubelet listen on
KUBELET_PORT="--kubelet-port=10250"
# Address range to use for services(Work unit of Kubernetes)
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"
# default admission control policies
KUBE_ADMISSION_CONTROL="--admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota"
# Add your own!
KUBE_API_ARGS="--client-ca-file=/srv/kubernetes/ca.crt --tls-cert-file=/srv/kubernetes/server.cert --tls-private-key-file=/srv/kubernetes/server.key"
EOF

  ### Controller Manager ###
cat >/etc/kubernetes/controller-manager << EOF
# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="--root-ca-file=/srv/kubernetes/ca.crt --service-account-private-key-file=/srv/kubernetes/server.key"
EOF
}

MASTER="master"
MINION="minion"
REMOVE="remove"

if [ "$1" == "$MASTER" ]
then
    echo master passed as argument
fi

if [ "$1" == "$MINION" ]
then
    echo minion passed as argument
fi

if [ "$1" == "$REMOVE" ]
then
    echo remove passed as argument
fi

if [ $# -ne 1 ]; then
    echo usage: $0 options
    echo Where options is one of 'master', 'minon' or 'remove'
    echo Example:
    echo kube_install.sh master
    exit 1
fi

name=$1


