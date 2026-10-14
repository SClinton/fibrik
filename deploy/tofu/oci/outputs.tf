output "public_ip" {
  description = "Point the Caddy domain's DNS A record here."
  value       = oci_core_instance.fibrik.public_ip
}

output "s3_endpoint" {
  description = "Use as storage.endpoint in values-free.yaml."
  value       = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
}

output "bucket" {
  value = oci_objectstorage_bucket.lake.name
}
