### File generated from Dockerfile.in; DO NOT EDIT.###
# Build arguments
ARG SOURCE_CODE=.
ARG CI_CONTAINER_VERSION="unknown"
ARG CI_CONTAINER_RELEASE="unknown"


# Use openshift4/ose-cli as base image
FROM registry.redhat.io/openshift4/ose-cli:v4.8 AS ocpcli


# Use ubi8/ubi-minimal as base image
FROM registry.redhat.io/ubi8/ubi-minimal:8.5

## Build args to be used at this step
ARG SOURCE_CODE
ARG CI_CONTAINER_VERSION
ARG CI_CONTAINER_RELEASE

## Install additional packages
RUN microdnf install -y openssl shadow-utils &&\
    microdnf clean all

## Create a non-root user with UID 1001 and switch to it
RUN useradd --uid 1001 --create-home --user-group --system deployer

## Set workdir directory to user home
WORKDIR /home/deployer

## Switch to a non-root user
USER deployer

## Copy odh-deployer scripts
COPY --from=ocpcli /usr/bin/oc /usr/local/bin
COPY --chown=deployer:root ${SOURCE_CODE}/deploy.sh .
COPY --chown=deployer:root ${SOURCE_CODE}/buildchain.sh .
COPY --chown=deployer:root ${SOURCE_CODE}/opendatahub.yaml .
COPY --chown=deployer:root ${SOURCE_CODE}/opendatahub-osd.yaml .
COPY --chown=deployer:root ${SOURCE_CODE}/rhods-monitoring.yaml .
COPY --chown=deployer:root ${SOURCE_CODE}/rhods-notebooks.yaml .
COPY --chown=deployer:root ${SOURCE_CODE}/rhods-osd-configs.yaml .
COPY --chown=deployer:root ${SOURCE_CODE}/cloud-resource-operator ./cloud-resource-operator
COPY --chown=deployer:root ${SOURCE_CODE}/monitoring ./monitoring
COPY --chown=deployer:root ${SOURCE_CODE}/consolelink ./consolelink
COPY --chown=deployer:root ${SOURCE_CODE}/groups ./groups
COPY --chown=deployer:root ${SOURCE_CODE}/jupyterhub ./jupyterhub
COPY --chown=deployer:root ${SOURCE_CODE}/network ./network
COPY --chown=deployer:root ${SOURCE_CODE}/partners ./partners

## Generate the checksum before we modify the manifest to be version specific.
## This checksum will be deployed in a configmap in a running rhods and so
## if the content other than the rhods/buildchain label value changes, the
## checksum will match
RUN sha256sum ./jupyterhub/cuda-11.0.3/manifests.yaml > ./manifest-checksum

## Update the labels with the specific version value
RUN sed -i 's,rhods/buildchain:.*,rhods/buildchain: cuda-'"${CI_CONTAINER_VERSION}-${CI_CONTAINER_RELEASE}"',g' \
       ./jupyterhub/cuda-11.0.3/manifests.yaml

ENTRYPOINT [ "./deploy.sh" ]


LABEL com.redhat.component="odh-deployer-container" \
      name="managed-open-data-hub/odh-deployer-rhel8" \
      version="${CI_CONTAINER_VERSION}" \
      release="${CI_CONTAINER_RELEASE}" \
      summary="odh-deployer" \
      io.openshift.expose-services="" \
      io.k8s.display-name="odh-deployer" \
      maintainer="['managed-open-data-hub@redhat.com']" \
      description="odh-deployer"
