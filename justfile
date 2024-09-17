export cluster_name := "cluster-api-kubevirt"
export kubevirt_version := "v1.2.0"
export calico_version := "v3.27.3"
export metallb_version := "v0.14.5"

create:
    kind create cluster --name {{cluster_name}} --config=kind-config.yaml

clean:
    kubectl delete cluster capi-quickstart
    kind delete cluster --name {{cluster_name}}

install: check-kubeconfig
    #!/usr/bin/env bash
    set -euxo pipefail

    kubectl create -f  https://raw.githubusercontent.com/projectcalico/calico/$calico_version/manifests/calico.yaml
    kubectl create -f https://raw.githubusercontent.com/metallb/metallb/$metallb_version/config/manifests/metallb-native.yaml
    kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/$kubevirt_version/kubevirt-operator.yaml
    kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/$kubevirt_version/kubevirt-cr.yaml

    kubectl wait pods -n metallb-system -l app=metallb,component=controller --for=condition=Ready --timeout=10m
    kubectl wait pods -n metallb-system -l app=metallb,component=speaker --for=condition=Ready --timeout=2m

    GW_IP=$(docker network inspect -f '{{{{range .IPAM.Config}}{{{{.Gateway}}{{{{end}}' kind)
    NET_IP=$(echo ${GW_IP} | sed -E 's|^([0-9]+\.[0-9]+)\..*$|\1|g')
    cat <<EOF | sed -E "s|172.19|${NET_IP}|g" | kubectl create -f -
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: capi-ip-pool
      namespace: metallb-system
    spec:
      addresses:
      - 172.19.255.200-172.19.255.250
    ---
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: empty
      namespace: metallb-system
    EOF

    kubectl wait -n kubevirt kv kubevirt --for=condition=Available --timeout=10m
    clusterctl init --infrastructure kubevirt --bootstrap talos --control-plane talos
    # clusterctl init --infrastructure kubevirt

    # kubectl create -f capi-quickstart.yaml

kt *args:
    @KUBECONFIG=`pwd`/capi-quickstart.kubeconfig kubectl {{args}}


get-capi-kubeconfig:
    clusterctl get kubeconfig capi-quickstart > capi-quickstart.kubeconfig

generate-capi-quickstart:
    #!/usr/bin/env bash
    set -euxo pipefail

    export CAPK_GUEST_K8S_VERSION="v1.30.5"
    export CRI_PATH="/var/run/containerd/containerd.sock"
    export NODE_VM_IMAGE_TEMPLATE="docker.io/trevex/talos-kubevirt:v1.7.6"

    clusterctl generate cluster capi-quickstart \
      --infrastructure="kubevirt" \
      --flavor lb \
      --kubernetes-version $CAPK_GUEST_K8S_VERSION \
      --control-plane-machine-count=1 \
      --worker-machine-count=1 \
      > capi-quickstart.yaml

    echo "Now edit the file by hand to use Talos instead..."

check-kubeconfig:
    kubectl config current-context | grep "kind-{{cluster_name}}"

get-kubevirt-version:
    curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt

build-talos:
    curl -L https://github.com/siderolabs/talos/releases/download/v1.7.6/metal-amd64.raw.xz -o talos.raw.xz
    xz -d talos.raw.xz
    qemu-img convert -O qcow2 talos.raw talos.qcow2
    docker build -t trevex/talos-kubevirt:v1.7.6 .
    docker push trevex/talos-kubevirt:v1.7.6
    rm talos.*
