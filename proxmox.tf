resource "random_shuffle" "node_shuffle" {
  input = var.proxmox_pve_node_name
}


resource "proxmox_virtual_environment_file" "talos" {
  for_each     = toset(var.proxmox_pve_node_name)
  node_name    = each.value
  datastore_id = var.talos-iso-datastoreid
  content_type = "iso"
  source_file {
    path      = "tmp/talos/talos-${var.talos_version}.qcow2"
    file_name = "talos-${var.talos_version}.img"
  }
}

resource "proxmox_virtual_environment_vm" "controller" {
  count           = var.controller_count
  name            = "${var.prefix}-${local.controller_nodes[count.index].name}"
  node_name       = var.proxmox_pve_node_name[count.index % 2]
  tags            = sort(concat(var.tags, ["controller"]))
  stop_on_destroy = true
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  operating_system {
    type = "l26"
  }
  cpu {
    type  = "host"
    cores = 2
  }
  memory {
    dedicated = 4 * 1024
  }
  vga {
    type = "qxl"
  }
  network_device {
    bridge = "vxvnet1"
    mtu    = 1
  }
  tpm_state {
    datastore_id = var.talos-iso-datastoreid-cp
    version      = "v2.0"
  }
  efi_disk {
    datastore_id = var.talos-iso-datastoreid-cp
    file_format  = "raw"
    type         = "4m"
  }
  disk {
    datastore_id = var.talos-iso-datastoreid-cp
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = 30
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_file.talos[var.proxmox_pve_node_name[count.index % 2]].id
  }
  agent {
    enabled = true
    trim    = true
  }
  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "${local.controller_nodes[count.index].address}/24"
        gateway = var.cluster_node_network_gateway
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  count           = var.worker_count
  name            = "${var.prefix}-${local.worker_nodes[count.index].name}"
  node_name       = var.proxmox_pve_node_name[count.index % 2]
  tags            = sort(concat(var.tags, ["worker"]))
  stop_on_destroy = true
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  operating_system {
    type = "l26"
  }
  cpu {
    type  = "host"
    cores = 4
  }
  memory {
    dedicated = 6 * 1024
  }
  vga {
    type = "qxl"
  }
  network_device {
    bridge = "vxvnet1"
    mtu    = 1
  }
  tpm_state {
    datastore_id = "local-lvm-1"
    version      = "v2.0"
  }
  efi_disk {
    datastore_id = "local-lvm-1"
    file_format  = "raw"
    type         = "4m"
  }
  disk {
    datastore_id = "local-lvm-1"
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = 40
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_file.talos[var.proxmox_pve_node_name[count.index % 2]].id
  }
  disk {
    datastore_id = "local-lvm-1"
    interface    = "scsi1"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = 60
    file_format  = "raw"
  }
  agent {
    enabled = true
    trim    = true
  }
  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "${local.worker_nodes[count.index].address}/24"
        gateway = var.cluster_node_network_gateway
      }
    }
  }
}
