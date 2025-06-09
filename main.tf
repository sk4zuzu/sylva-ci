terraform {
  required_providers {
    opennebula = {
      source  = "terraform.local/local/opennebula"
      version = "0.0.1"
    }
  }
}

provider "opennebula" {
  endpoint      = "http://10.2.11.40:2633/RPC2"
  flow_endpoint = "http://10.2.11.40:2474"
  username      = "oneadmin"
  password      = "asd"
}

resource "random_id" "asd" {
  byte_length = 4
}

data "opennebula_virtual_network" "asd" {
  for_each = { service = null }
  name     = each.key
}

resource "opennebula_image" "asd" {
  for_each     = { nixos = "https://d24fmfybwxpuhu.cloudfront.net/nixos-25.05.803297.10d7f8d34e5e-20250609.qcow2" }
  name         = "${each.key}-${random_id.asd.id}"
  datastore_id = "1"
  persistent   = false
  permissions  = "642"
  dev_prefix   = "vd"
  driver       = "qcow2"
  path         = each.value
}

locals {
  user_data = {
    hydra = {
      write_files = [
        {
          path        = "/var/tmp/setup-sylva-ci.sh"
          owner       = "root:root"
          permissions = "u=rwx,go=rx"
          encoding    = "b64"
          content     = base64encode(file("${path.module}/setup-sylva-ci.sh"))
        },
      ]
      runcmd = [
        "/run/current-system/sw/bin/bash --login /var/tmp/setup-sylva-ci.sh",
      ]
    }
  }
}

resource "opennebula_template" "asd" {
  for_each    = { hydra = opennebula_image.asd["nixos"].id }
  name        = "${each.key}-${random_id.asd.id}"
  permissions = "642"
  cpu         = "0.5"
  vcpu        = "1"
  memory      = 16384

  context = {
    SET_HOSTNAME       = "sylva-ci"
    NETWORK            = "YES"
    TOKEN              = "YES"
    SSH_PUBLIC_KEY     = "$USER[SSH_PUBLIC_KEY]"
    USER_DATA_ENCODING = "base64"
    USER_DATA          = base64encode(join("\n", ["#cloud-config", yamlencode(local.user_data[each.key])]))
  }

  os {
    arch = "x86_64"
    boot = ""
  }

  disk {
    image_id = each.value
    size     = 65536
  }

  nic {
    model      = "virtio"
    network_id = data.opennebula_virtual_network.asd["service"].id
 }

  graphics {
    keymap = "en-us"
    listen = "0.0.0.0"
    type   = "VNC"
  }
}

resource "opennebula_service_template" "asd" {
  for_each    = { hydra = opennebula_template.asd["hydra"].id }
  name        = "${each.key}-${random_id.asd.id}"
  permissions = "642"

  template = jsonencode({
    TEMPLATE = {
      BODY = {
        name       = "${each.key}-${random_id.asd.id}"
        deployment = "straight"
        roles = [
          {
            name                = "hydra"
            type                = "vm"
            cardinality         = 1
            min_vms             = 1
            cooldown            = 5
            elasticity_policies = []
            scheduled_policies  = []
            template_id         = tonumber(each.value)
          },
        ]
      }
    }
  })
}

resource "opennebula_service" "asd" {
  for_each = { hydra = opennebula_service_template.asd["hydra"].id }
  name     = "${each.key}-${random_id.asd.id}"

  template_id = each.value

  extra_template = jsonencode({
    roles = [{ cardinality = 1 }]
  })

  timeouts {
    create = "5m"
    delete = "5m"
  }
}
