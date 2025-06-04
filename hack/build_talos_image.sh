#!/bin/bash
set -euo pipefail

# Version Talos
# renovate: datasource=github-releases depName=siderolabs/talos
talos_version="1.10.3"

# Extensions
# renovate: datasource=docker depName=ghcr.io/siderolabs/qemu-guest-agent
talos_qemu_guest_agent_extension_tag="10.0.2"
# renovate: datasource=docker depName=ghcr.io/siderolabs/drbd
talos_drbd_extension_tag="9.2.13-v1.10.0"
# renovate: datasource=docker depName=ghcr.io/siderolabs/spin
talos_spin_extension_tag="v0.19.0"

# Fonction de construction de l'image Talos
function build_talos_image {
  local talos_version_tag="v$talos_version"
  rm -rf tmp/talos
  mkdir -p tmp/talos
  cat >"tmp/talos/talos-$talos_version.yml" <<EOF
arch: amd64
platform: nocloud
secureboot: false
version: $talos_version_tag
customization:
  extraKernelArgs:
    - net.ifnames=0
input:
  kernel:
    path: /usr/install/amd64/vmlinuz
  initramfs:
    path: /usr/install/amd64/initramfs.xz
  baseInstaller:
    imageRef: ghcr.io/siderolabs/installer:$talos_version_tag
  systemExtensions:
    - imageRef: ghcr.io/siderolabs/qemu-guest-agent:$talos_qemu_guest_agent_extension_tag
    - imageRef: ghcr.io/siderolabs/drbd:$talos_drbd_extension_tag
    - imageRef: ghcr.io/siderolabs/spin:$talos_spin_extension_tag
output:
  kind: image
  imageOptions:
    diskSize: $((2*1024*1024*1024))
    diskFormat: raw
  outFormat: raw
EOF
  docker run --rm -i \
    -v $PWD/tmp/talos:/secureboot:ro \
    -v $PWD/tmp/talos:/out \
    -v /dev:/dev \
    --privileged \
    "ghcr.io/siderolabs/imager:$talos_version_tag" \
    - < "tmp/talos/talos-$talos_version.yml"
  local img_path="tmp/talos/talos-$talos_version.qcow2"
  qemu-img convert -O qcow2 tmp/talos/nocloud-amd64.raw $img_path
  qemu-img info $img_path
}

# Appel de la fonction pour construire l'image Talos
build_talos_image
