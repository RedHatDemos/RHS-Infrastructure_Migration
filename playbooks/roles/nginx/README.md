Nginx Role
=========

A role to deploy, and configure a Nginx webserver as load balancer in RHEL7 / CentOS7

Requirements
------------

The system to run this role has to be subscribed (if RHEL), and configured with the base, optional and extras repos.


It can be done in RHEL with the following command (once subscribed)
```
subscription-manager repos --disable='*' --enable='rhel-x86_64-server-7' --enable='rhel-x86_64-server-extras-7' --enable='rhel-x86_64-server-optional-7'
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
