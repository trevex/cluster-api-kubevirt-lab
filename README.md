# Testing Cluster API with Kubevirt

## 1. Create the kind cluster
```bash
just create
```

## 2. Install Kubevirt, MetalLB, Calico and Cluster API incl a Workload Cluster
```bash
just install
```

## 3. Test the workload cluster

```bash
clusterctl describe cluster capi-quickstart
just get-capi-kubeconfig
just kt get no # access tenant
```
