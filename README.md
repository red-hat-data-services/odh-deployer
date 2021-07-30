# odh-deployer
Deployment container for Open Data Hub

This container is meant to be run alongside the opendatahub operator.
It will create the ODH custom resource (KfDef) to trigger the
installation of the components specified in opendatahub.yaml 
(or opendatahub-osd.yaml if on OpenShift Dedicated)
