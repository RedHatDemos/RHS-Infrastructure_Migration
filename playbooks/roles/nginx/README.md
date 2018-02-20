Nginx Role
=========

A role to deploy, and configure a Nginx webserver as load balancer in RHEL7 / CentOS7

Requirements
------------

The system to run this role has to be subscribed (if RHEL), and configured with the base repo.

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
