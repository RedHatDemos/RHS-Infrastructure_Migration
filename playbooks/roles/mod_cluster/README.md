Mod_Cluster Role
=========

A role to deploy, and configure a Mod_Cluster + Apache HTTPD webserver as load balancer in RHEL7 / CentOS7

Requirements
------------

The system to run this role has to be subscribed (if RHEL), and configured with the base, optional and extras repos. Then add EPEL.


It can be done in RHEL with the following commands (once subscribed):
```
subscription-manager repos --disable='*' --enable='rhel-7-server-rpms' --enable='jb-coreservices-1-for-rhel-7-server-rpms'
```

Role Variables
--------------

TODO (Currently hardcoded IP for App Servers)

Example Playbook
----------------

Example playbook is quite simple:

    ---
    - hosts: lb.example.com
      roles:
        - mod_cluster

License
-------

Apache 2.0

Author Information
------------------

Miguel Pérez Colino 
