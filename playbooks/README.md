# RHS - Optimize IT - Infrastructure Migration - Playbooks
Red Hat Solutions - Optimize IT - Infrastructure Migration - Ansible playbooks

This is a set of Ansible Playbooks and hosts to deploy
* One Apache Mod_cluster server (lb.example.com)
* Two JBoss EAP servers in domain mode (jboss0.example.com, jboss1.example.com) 
* One PostgreSQL database (db.example.com)

The VMs to deploy all the software have to be installed with Red Hat Enterprise Linux 7.

There are 4 main playbooks:
* prepare_hosts.yml - To register VMs in the Red Hat CDN (requires to create a vars.yml with your credentials)
* jboss-eap.yml - To deploy and configure JBoss EAP 7 servers in domain mode (uses JBoss RPMs to deploy)
* mod_cluster.yml -  To deploy and configure an mod_cluster server as balancer
* postgresql.yml - To deploy and configure a PostgreSQL datbase as app backend

This is currently work in progress. Please use it with caution.
Please, report issues with documentation and/or lab in the issues section of this repo.

Tested in the [Red Hat Product Demo System](https://rhpds.redhat.com)

