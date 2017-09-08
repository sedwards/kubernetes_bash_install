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

setup_minion1 () {
cat /etc/kubernetes/kubelet  << EOF
# kubelet bind ip address(Provide private ip of minion)
KUBELET_ADDRESS="--address=0.0.0.0"
# port on which kubelet listen
KUBELET_PORT="--port=10250"
# leave this blank to use the hostname of server
KUBELET_HOSTNAME="--hostname-override=172.16.0.2"
# Location of the api-server
KUBELET_API_SERVER="--api-servers=http://172.16.0.1:8080"
# Add your own!
KUBELET_ARGS=""
EOF
}

setup_minion2 () {
cat /etc/kubernetes/kubelet  << EOF
# kubelet bind ip address(Provide private ip of minion)
KUBELET_ADDRESS="--address=0.0.0.0"
# port on which kubelet listen
KUBELET_PORT="--port=10250"
# leave this blank to use the hostname of server
KUBELET_HOSTNAME="--hostname-override=172.16.0.3"
# Location of the api-server
KUBELET_API_SERVER="--api-servers=http://172.16.0.1:8080"
# Add your own!
KUBELET_ARGS=""
EOF
}

start_master (){
  systemctl enable kube-apiserver
  systemctl start kube-apiserver
  systemctl enable kube-controller-manager
  systemctl start kube-controller-manager
  systemctl start kube-scheduler
  systemctl start kube-scheduler
  systemctl enable flanneld
  systemctl start flanneld
}

start_minion ()
{
  systemctl enable kube-proxy
  systemctl start kube-proxy
  systemctl enable kubelet
  systemctl start kubelet
  systemctl enable flanneld
  systemctl start flanneld
  systemctl enable docker
  systemctl start docker
}

###########################################
## Main

MASTER="master"
MINION1="minion1"
MINION2="minion2"
REMOVE="remove"

if [ "$1" == "$MASTER" ]
then
    echo master passed as argument
    install_common
    setup_etcd_master
    systemctl start etcd
    etcdctl mkdir /kube-centos/network
    ### allocates the 172.30.0.0/16 subnet to the Flannel network
    etcdctl mk /kube-centos/network/config "{ \"Network\": \"172.30.0.0/16\", \"SubnetLen\": 24, \"Backend\": { \"Type\": \"vxlan\" } }"
    start_master
fi

if [ "$1" == "$MINION1" ]
then
    echo minion passed as argument
    install_common
    setup_minion1
    start_minion
fi

if [ "$1" == "$MINION2" ]
then
    echo minion passed as argument
    install_common
    setup_minion2
    start_minion
fi

if [ "$1" == "$REMOVE" ]
then
    echo remove passed as argument
    systemctl stop kube-apiserver
    systemctl stop kube-controller-manager
    systemctl stop kube-scheduler
    systemctl stop kube-scheduler
    systemctl stop flanneld
    systemctl stop kube-proxy
    systemctl stop kubelet
    systemctl stop docker
    remove_common
fi

if [ $# -ne 1 ]; then
    echo -e ###########################################
    echo usage: $0 options
    echo -e ###########################################
    echo Where options is one of 'master', 'minon1', 'minion2' or 'remove'
    echo -e ###########################################
    echo Example:
    echo kube_install.sh master
    echo -e ###########################################
    exit 1
fi

#EOF

