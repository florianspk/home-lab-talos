# renovate: datasource=github-releases depName=piraeusdatastore/piraeus-operator
piraeus_operator_version="2.9.0"
kubectl apply --server-side -k "https://github.com/piraeusdatastore/piraeus-operator//config/default?ref=v$piraeus_operator_version"
kubectl wait pod --timeout=15m --for=condition=Ready -n piraeus-datastore -l app.kubernetes.io/component=piraeus-operator
kubectl apply -n piraeus-datastore -f - <<'EOF'
apiVersion: piraeus.io/v1
kind: LinstorSatelliteConfiguration
metadata:
  name: talos-loader-override
spec:
  podTemplate:
    spec:
      initContainers:
        - name: drbd-shutdown-guard
          $patch: delete
        - name: drbd-module-loader
          $patch: delete
      volumes:
        - name: run-systemd-system
          $patch: delete
        - name: run-drbd-shutdown-guard
          $patch: delete
        - name: systemd-bus-socket
          $patch: delete
        - name: lib-modules
          $patch: delete
        - name: usr-src
          $patch: delete
        - name: etc-lvm-backup
          hostPath:
            path: /var/etc/lvm/backup
            type: DirectoryOrCreate
        - name: etc-lvm-archive
          hostPath:
            path: /var/etc/lvm/archive
            type: DirectoryOrCreate
EOF
  kubectl apply -f - <<EOF
apiVersion: piraeus.io/v1
kind: LinstorCluster
metadata:
  name: linstor
EOF
  kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
provisioner: linstor.csi.linbit.com
metadata:
  name: linstor-lvm-r1
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  csi.storage.k8s.io/fstype: xfs
  linstor.csi.linbit.com/autoPlace: "1"
  linstor.csi.linbit.com/storagePool: lvm
EOF
  kubectl wait pod --timeout=15m --for=condition=Ready -n piraeus-datastore -l app.kubernetes.io/name=piraeus-datastore
  kubectl wait LinstorCluster/linstor --timeout=15m --for=condition=Available
  local workers="$(terraform output -raw workers)"
  local nodes=($(echo "$workers" | tr ',' ' '))
  for ((n=0; n<${#nodes[@]}; ++n)); do
    local node="w$((n))"
    while ! kubectl linstor storage-pool list --node "$node" >/dev/null 2>&1; do sleep 3; done
    if ! kubectl linstor storage-pool list --node "$node" --storage-pool lvm | grep -q lvm; then
      kubectl linstor physical-storage create-device-pool \
        --pool-name lvm \
        --storage-pool lvm \
        lvm \
        "$node" \
        /dev/sdb
    fi
  done

kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
provisioner: linstor.csi.linbit.com
metadata:
  name: linstor-lvm-media
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  csi.storage.k8s.io/fstype: xfs
  linstor.csi.linbit.com/autoPlace: "1"
  linstor.csi.linbit.com/storagePool: lvm-media
EOF
for ((n=0; n<${#nodes[@]}; ++n)); do
    local node="w$((n))"
    while ! kubectl linstor storage-pool list --node "$node" >/dev/null 2>&1; do sleep 3; done
    if ! kubectl linstor storage-pool list --node "$node" --storage-pool lvm-media | grep -q lvm-media; then
      kubectl linstor physical-storage create-device-pool \
        --pool-name lvm-media \
        --storage-pool lvm-media \
        lvm \
        "$node" \
        /dev/sdc
    fi
done
