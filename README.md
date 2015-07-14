rsDSCCert
===========
Module for DSC resources to maintain DSC pullserver certificates on the Pullserver and Client nodes.


Release Notes
-------------


- **v2.0**
----------

**WARNING** - Incompatible with pre-v3.0 platform!

Feature Additions
-----------------

- RS_rsGetPublicCert resource
	- PullServerAddress and PullServerPort variables added(not required).
		- Allows "warm" change of PullServer address, facilitating DNS / configuration migration.

	- Additional Test logic to validate new variables against local nodeinfo.json

	- Additional Set logic accounting for replaced PullServers
		- Will aquire new PullServer Hostname and Public Cert from the HTTPS endpoint.