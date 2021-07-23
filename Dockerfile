FROM registry.access.redhat.com/ubi8/ubi-minimal

ENV TMPDIR /tmp
ENV HOME /home/deployer

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
COPY opendatahub.yaml $HOME
COPY rhods-monitoring.yaml $HOME
COPY rhods-notebooks.yaml $HOME
ADD monitoring $HOME/monitoring
ADD consolelink $HOME/consolelink
ADD groups $HOME/groups
ADD jupyterhub $HOME/jupyterhub
ADD partners $HOME/partners
ADD network $HOME/network

RUN chmod 755 $HOME/deploy.sh && \
    chmod 644 $HOME/opendatahub.yaml && \
    chmod 644 $HOME/rhods-monitoring.yaml && \
    chmod 644 $HOME/rhods-notebooks.yaml && \
    chmod 644 -R $HOME/monitoring && \
    chmod 644 -R $HOME/groups && \
    chmod 644 -R $HOME/jupyterhub && \
    chmod 644 -R $HOME/network && \
    chown 1001:0 -R $HOME &&\
    chmod ug+rwx -R $HOME

ARG builddate="(unknown)"
ARG version="(unknown)"
ARG vcs="(unknown)"

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
