Nginx Role
=========

A role to deploy, and configure a Nginx webserver as load balancer in RHEL7 / CentOS7

Requirements
------------

The system to run this role has to be subscribed (if RHEL), and configured with the base, optional and extras repos. Then add EPEL.


It can be done in RHEL with the following commands (once subscribed):
```
subscription-manager repos --disable='*' --enable='rhel-7-server-rpms' --enable='rhel-7-server-extras-rpms' --enable='rhel-7-server-optional-rpms'nal-7'
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
```

Role Variables
--------------

TODO (Currently hardcoded IP for App Servers)

Example Playbook
----------------

Example playbook is quite simple:

    ---
    - hosts: nginx.example.com
      roles:
        - nginx

License
-------

Apache 2.0

Author Information
------------------

Miguel Pérez Colino 
