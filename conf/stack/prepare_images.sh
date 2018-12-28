openstack overcloud container image prepare --prefix=openstack- \
--namespace=registry.access.redhat.com/rhosp13 \
--push-destination=10.100.0.20:8787 --output-env-file=/home/stack/templates/10-overcloud_images.yaml \
--output-images-file /home/stack/local_registry_images.yaml

