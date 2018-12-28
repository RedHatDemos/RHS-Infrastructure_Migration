subscription-manager repos --disable=*
subscription-manager repos \
--enable=rhel-7-server-rpms \
--enable=rhel-7-server-extras-rpms \
--enable=rhel-7-server-rh-common-rpms \
--enable=rhel-7-server-openstack-13-devtools-rpms \
--enable=rhel-7-server-openstack-13-tools-rpms \
--enable=rhel-7-server-openstack-13-rpms \
--enable=rhel-7-server-openstack-13-optools-rpms \
--enable=rhel-ha-for-rhel-7-server-rpms
