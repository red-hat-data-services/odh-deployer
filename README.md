# RHODS Deployer

Deployment container for Red Hat OpenShift Data Science (RHODS).

This container is meant to be run alongside the OpenDataHub operator. It will
create the ODH custom resource (KfDef) to trigger the installation of the
components specified in **opendatahub.yaml** (or **opendatahub-osd.yaml** if on
OpenShift Dedicated).

## Building container

Build the image locally by running this command:

```
podman login -u ${USER} quay.io
podman login -u ${USER} registry.redhat.io
make build-img -e CONTAINER_REPO=quay.io/${USER}
```

Push the image to your registry:

```
make push-img -e CONTAINER_REPO=quay.io/${USER}
```
