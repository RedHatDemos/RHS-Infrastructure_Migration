JBoss EAP Domain Role
=========

A role to deploy, and configure two JBoss servers as master adn slave in RHEL7 / CentOS7

Requirements
------------

The system to run this role has to be subscribed (if RHEL), and configured with the base repo, adn the JBoss EAP repo.

It can be done in RHEL with the following command (once subscribed)
```
subscription-manager repos --disable='*' --enable='rhel-x86_64-server-7' --enable='rhel-x86_64-server-extras-7' --enable='rhel-x86_64-server-optional-7'
```

Role Variables
--------------

TODO

Example Playbook
----------------

Example playbook is quite simple:

    ---
    - hosts: jboss[0:1].example.com
      roles:
        - jboss

License
-------

Apache 2.0

Author Information
------------------

Miguel Pérez Colino 

Based on work by Sergio Ocón Cardenas:
https://github.com/chargio/postgresql-vagrant
