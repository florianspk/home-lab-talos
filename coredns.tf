# CoreDNS géré ici (cluster.coreDNS.disabled = true dans talos.tf) au lieu du manifest par défaut de Talos,
# pour garder le forward vers 1.1.1.1 / 8.8.8.8 : le Corefile de Talos fait `forward . /etc/resolv.conf`,
# c'est-à-dire vers le hostDNS (169.254.116.108, forwardKubeDNSToHost), qui n'est pas fiable avec
# Cilium bpf.masquerade=true. `talosctl upgrade-k8s` réapplique ces objets (mêmes noms, pas de prune).
# Copie des manifests 11-core-dns / 11-core-dns-svc de Talos 1.14.6 (`talosctl get manifests 11-core-dns -o yaml`),
# seule la ligne forward diffère. L'image n'est plus montée par Talos : la vérifier à chaque upgrade de Talos.
locals {
  coredns_image    = "registry.k8s.io/coredns/coredns:v1.14.7"
  coredns_manifest = <<-EOF
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: coredns
    namespace: kube-system
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    labels:
      kubernetes.io/bootstrapping: rbac-defaults
    name: system:coredns
  rules:
    - apiGroups:
        - ""
      resources:
        - endpoints
        - services
        - pods
        - namespaces
      verbs:
        - list
        - watch
    - apiGroups:
        - discovery.k8s.io
      resources:
        - endpointslices
      verbs:
        - list
        - watch
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    annotations:
      rbac.authorization.kubernetes.io/autoupdate: "true"
    labels:
      kubernetes.io/bootstrapping: rbac-defaults
    name: system:coredns
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:coredns
  subjects:
    - kind: ServiceAccount
      name: coredns
      namespace: kube-system
  ---
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: coredns
    namespace: kube-system
  data:
    Corefile: |-
      .:53 {
          errors
          health {
              lameduck 5s
          }
          ready
          log . {
              class error
          }
          prometheus :9153

          kubernetes cluster.local in-addr.arpa ip6.arpa {
              pods insecure
              fallthrough in-addr.arpa ip6.arpa
              ttl 30
          }
          forward . 1.1.1.1 8.8.8.8 {
             max_concurrent 1000
          }
          cache 30 {
             disable success cluster.local
             disable denial cluster.local
          }
          loop
          reload
          loadbalance
      }
  ---
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    labels:
      k8s-app: kube-dns
      kubernetes.io/name: CoreDNS
    name: coredns
    namespace: kube-system
  spec:
    replicas: 2
    selector:
      matchLabels:
        k8s-app: kube-dns
    strategy:
      rollingUpdate:
        maxUnavailable: 1
      type: RollingUpdate
    template:
      metadata:
        labels:
          k8s-app: kube-dns
      spec:
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
                - matchExpressions:
                    - key: kubernetes.io/os
                      operator: In
                      values:
                        - linux
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: k8s-app
                        operator: In
                        values:
                          - kube-dns
                  topologyKey: kubernetes.io/hostname
                weight: 100
        containers:
          - args:
              - -conf
              - /etc/coredns/Corefile
            env:
              - name: GOMEMLIMIT
                value: 161MiB
            image: ${local.coredns_image}
            imagePullPolicy: IfNotPresent
            livenessProbe:
              failureThreshold: 5
              httpGet:
                path: /health
                port: 8080
                scheme: HTTP
              initialDelaySeconds: 60
              successThreshold: 1
              timeoutSeconds: 5
            name: coredns
            ports:
              - containerPort: 53
                name: dns
                protocol: UDP
              - containerPort: 53
                name: dns-tcp
                protocol: TCP
              - containerPort: 9153
                name: metrics
                protocol: TCP
            readinessProbe:
              httpGet:
                path: /ready
                port: 8181
                scheme: HTTP
            resources:
              limits:
                memory: 170Mi
              requests:
                cpu: 100m
                memory: 70Mi
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                add:
                  - NET_BIND_SERVICE
                drop:
                  - ALL
              readOnlyRootFilesystem: true
            volumeMounts:
              - mountPath: /etc/coredns
                name: config-volume
                readOnly: true
        dnsPolicy: Default
        nodeSelector:
          kubernetes.io/os: linux
        priorityClassName: system-cluster-critical
        serviceAccountName: coredns
        tolerations:
          - effect: NoSchedule
            key: node-role.kubernetes.io/control-plane
            operator: Exists
          - effect: NoSchedule
            key: node.cloudprovider.kubernetes.io/uninitialized
            operator: Exists
        volumes:
          - configMap:
              items:
                - key: Corefile
                  path: Corefile
              name: coredns
            name: config-volume
  ---
  apiVersion: v1
  kind: Service
  metadata:
    annotations:
      prometheus.io/port: "9153"
      prometheus.io/scrape: "true"
    labels:
      k8s-app: kube-dns
      kubernetes.io/cluster-service: "true"
      kubernetes.io/name: CoreDNS
    name: kube-dns
    namespace: kube-system
  spec:
    clusterIP: 10.96.0.10
    clusterIPs:
      - 10.96.0.10
    ipFamilies:
      - IPv4
    ipFamilyPolicy: SingleStack
    ports:
      - name: dns
        port: 53
        protocol: UDP
        targetPort: 53
      - name: dns-tcp
        port: 53
        protocol: TCP
        targetPort: 53
      - name: metrics
        port: 9153
        protocol: TCP
        targetPort: 9153
    selector:
      k8s-app: kube-dns
  EOF
}
