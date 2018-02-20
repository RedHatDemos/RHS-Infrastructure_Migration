PostgreSQL Role
=========

A role to deploy, initialize and configure a PostgreSQL database in RHEL7 / CentOS7

Requirements
------------

The system to run this role has to be subscribed (if RHEL), and configured with the base repo

Role Variables
--------------

TODO

Example Playbook
----------------

Example playbook is quite simple:

    ---
    - hosts: db.example.com
      roles:
        - postgresql

License
-------

Apache 2.0

Author Information
------------------

Miguel Pérez Colino 

Based on work by Sergio Ocón Cardenas:
https://github.com/chargio/postgresql-vagrant
