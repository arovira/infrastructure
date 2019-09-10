Description
-------------------------------------

This repo can be used to create GKE clusters using terraform templates.

terraform.sh script is mainly to make sure the state can be maintened on the artifactory, in case mutiple people are working on the same templates and as wrapper to avoid inputting values at runtime.

The variables.tf file consists of the values needed for the main template

TODO: 
Post creation of the GKE cluster the bootstrap script would run, which would take care of the services, dns entries, cert manager, ingress services.


Running the templates
-------------------------------------

```
-- clone this repo onto your local
-- ./terraform.sh <cluster-name> <operation>
-- 
```
