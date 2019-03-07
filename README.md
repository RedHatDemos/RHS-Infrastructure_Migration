# Red Hat Solutions - Infrastructure Migration 1.1

Please, report issues with documentation and/or lab in the [issues](issues) section of this repo. Feel free to propose updates and changes in the [pull request](pulls) section, preferrably as ansible playbooks and/or ASCII doc files.

## For TL;DR check this video
[![IMS 1.1 Video](https://img.youtube.com/vi/uBM-1mJxJ5g/0.jpg)](https://www.youtube.com/watch?v=uBM-1mJxJ5g)

## Go ahead, get your hands dirty!

* [Infrastructure Migration Solution - Lab Guides](doc)
* [Video Introduction: Virtualization and Infrastructure Migration Technical Overview RH018](https://www.redhat.com/en/services/training/rh018-virtualization-and-infrastructure-migration-technical-overview)

## Enablement Environment - Infratructure Migration Solution 1.1 GA
```
  0.30 Fixed Ip in workstation (issues with DHCP)
  0.29 Ansible updates to CF cleanup
  0.28 Update CF to 5.10.0.33 GA; Added interface in service network to CF; Ignore errors in start_vms
  0.27 New playbook for auto startup of VMs
  0.26 Added pre-migration playbook for lb
  0.25 Added security rules for TCP and ICMP in OSP
  0.24 Ansible VM Autostarts resructured
  0.23 Disable nested virt in OSP. Fixed lb interfaces.
  0.22 Enabled nested virt in OSP Computes. Fixed config mistakes in CF. Cleanups.
  0.21 Updating CFME to 5.10.0.31
  0.20 Minor fixes
  0.19 Configured conversion host for OSP
  0.18 Fixed ip for apps.example.com. Renamed OSP resources
  0.17 Created bigger conversion host, updated hosts on workstation. Added volume type. Infra mapping works. 
  0.16 Increase CPU cores in Computes and add the Conversion host. Resizing of Director and Computes.
  0.15 Redeployed OSP with new networking.
  0.14 OSP deployed with public API on 192.168.10.16
  0.13 CF reconfigured with prov. networks
  0.12 Update CFME 5.10.0.29-1
  0.11 Updated RHV and reconfigured conversion host.
  0.10 Updated CFME to 5.10.0.28-1
  0.9 Fixed internal DNS Fixed interface naming in VMs Added configuration for conversion host in CF
  0.8 Reconfigure network interfaces in vSphere and VMs
  0.7 Updating CF to 5.9.5
  0.6 Added interfaces to CF and Workstation to access services
  0.5 Added Networks to RHV
  0.4 Added OSP 13 with Director
  0.3 Rearranged network
  0.2 Added impi and director hosts
  0.1 Added Cloned environment from 1.0 to 1.1
```
