# One Always Free Ampere A1 VM running k3s, a block volume for its data, and
# an Object Storage bucket. Nothing in the chart or the application names
# OCI; this module is the only OCI-specific code (initial-stack.md §0 rule 4).

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  ad = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

resource "oci_core_vcn" "fibrik" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.42.0.0/16"]
  display_name   = "fibrik"
  dns_label      = "fibrik"
}

resource "oci_core_internet_gateway" "fibrik" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.fibrik.id
  display_name   = "fibrik"
}

resource "oci_core_route_table" "fibrik" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.fibrik.id
  display_name   = "fibrik"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.fibrik.id
  }
}

resource "oci_core_security_list" "fibrik" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.fibrik.id
  display_name   = "fibrik"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # HTTPS only (Caddy obtains its certificate with TLS-ALPN on 443).
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.admin_cidr == "" ? [] : [var.admin_cidr]
    content {
      source   = ingress_security_rules.value
      protocol = "6"
      tcp_options {
        min = 22
        max = 22
      }
    }
  }
}

resource "oci_core_subnet" "fibrik" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.fibrik.id
  cidr_block        = "10.42.1.0/24"
  display_name      = "fibrik"
  dns_label         = "nodes"
  route_table_id    = oci_core_route_table.fibrik.id
  security_list_ids = [oci_core_security_list.fibrik.id]
}

resource "oci_core_instance" "fibrik" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.ad
  display_name        = "fibrik"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.fibrik.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      k3s_version = var.k3s_version
    }))
  }
}

resource "oci_core_volume" "data" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.ad
  display_name        = "fibrik-data"
  size_in_gbs         = var.data_volume_gb
}

resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.fibrik.id
  volume_id       = oci_core_volume.data.id
  device          = "/dev/oracleoci/oraclevdb"
}

resource "oci_objectstorage_bucket" "lake" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = var.bucket_name
  access_type    = "NoPublicAccess"
}
