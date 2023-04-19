FROM registry.access.redhat.com/ubi8/ubi-minimal:8.7

ARG builddate="unknown"
ARG version="unknown"
ARG vcs="unknown"

ENV TMPDIR /tmp
ENV HOME /home/deployer
ENV RHODS_VERSION ${version}

RUN microdnf install -y openssl shadow-utils tar gzip &&\
    microdnf clean all &&\
    rm -rf /var/cache/yum

ADD https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz $TMPDIR/
RUN tar -C /usr/local/bin -xvf $TMPDIR/oc.tar.gz && \
    chmod +x /usr/local/bin/oc && \
    rm $TMPDIR/oc.tar.gz &&\
    mkdir -p $HOME

RUN useradd --uid 1001 --create-home --user-group --system deployer
WORKDIR $HOME
USER deployer

COPY --chown=deployer:root deploy.sh .
COPY --chown=deployer:root kfdefs ./kfdefs
COPY --chown=deployer:root monitoring ./monitoring
COPY --chown=deployer:root partners ./partners
COPY --chown=deployer:root network ./network
COPY --chown=deployer:root odh-dashboard ./odh-dashboard
COPY --chown=deployer:root pod-security-rbac ./pod-security-rbac

LABEL org.label-schema.build-date="$builddate" \
      org.label-schema.description="Pod to deploy the CR for Open Data Hub" \
      org.label-schema.license="Apache-2.0" \
      org.label-schema.name="ODH deployer" \
      org.label-schema.vcs-ref="$vcs" \
      org.label-schema.vendor="Red Hat" \
      org.label-schema.version="$version"

ENTRYPOINT [ "./deploy.sh" ]
