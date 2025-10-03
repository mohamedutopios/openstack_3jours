output "fips" {
  value = {
    kafka    = openstack_networking_floatingip_v2.fip_kafka.address
    spark    = openstack_networking_floatingip_v2.fip_spark.address
    postgres = openstack_networking_floatingip_v2.fip_postgres.address
  }
}