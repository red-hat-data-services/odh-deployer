FROM registry.access.redhat.com/ubi8/ubi-minimal

ARG builddate="unknown"
ARG version="unknown"
ARG vcs="unknown"

ENV TMPDIR /tmp
ENV HOME /home/deployer
ENV RHODS_VERSION ${version}

RUN microdnf update -y && \
    microdnf install -y \
      bash \
      tar \
      gzip \
      openssl \
    && microdnf clean all && \
    rm -rf /var/cache/yum

ADD https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz $TMPDIR/
RUN tar -C /usr/local/bin -xvf $TMPDIR/oc.tar.gz && \
    chmod +x /usr/local/bin/oc && \
    rm $TMPDIR/oc.tar.gz &&\
    mkdir -p $HOME

COPY deploy.sh $HOME
ADD kfdefs $HOME/kfdefs
ADD model-mesh $HOME/model-mesh
ADD monitoring $HOME/monitoring
ADD consolelink $HOME/consolelink
ADD partners $HOME/partners
ADD network $HOME/network
ADD odh-dashboard $HOME/odh-dashboard
ADD pod-security-rbac $HOME/pod-security-rbac

RUN chmod 755 $HOME/deploy.sh && \
    chmod 644 -R $HOME/kfdefs && \
    chmod 644 -R $HOME/model-mesh && \
    chmod 644 -R $HOME/monitoring && \
    chmod 644 -R $HOME/network && \
    chmod 644 -R $HOME/odh-dashboard && \
    chmod 644 -R $HOME/pod-security-rbac && \
    chown 1001:0 -R $HOME &&\
    chmod ug+rwx -R $HOME

LABEL org.label-schema.build-date="$builddate" \
      org.label-schema.description="Pod to deploy the CR for Open Data Hub" \
      org.label-schema.license="Apache-2.0" \
      org.label-schema.name="ODH deployer" \
      org.label-schema.vcs-ref="$vcs" \
      org.label-schema.vendor="Red Hat" \
      org.label-schema.version="$version"

WORKDIR $HOME
ENTRYPOINT [ "./deploy.sh" ]

USER 1001
