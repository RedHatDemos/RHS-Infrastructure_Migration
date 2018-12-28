openstack overcloud deploy --templates \
-e /home/stack/templates/00-node_info.yaml \
-e /home/stack/templates/10-overcloud-images.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
-e /home/stack/templates/20-network-environment.yaml \
