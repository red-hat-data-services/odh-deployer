FROM registry.access.redhat.com/ubi8/ubi-minimal

ENV TMPDIR /tmp
ENV HOME /home/deployer

RUN microdnf update -y && \
    microdnf install -y \
      bash \
      tar \
      gzip \
    && microdnf clean all && \
    rm -rf /var/cache/yum

ADD https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz $TMPDIR/
RUN tar -C /usr/local/bin -xvf $TMPDIR/oc.tar.gz && \
    chmod +x /usr/local/bin/oc && \
    rm $TMPDIR/oc.tar.gz

COPY deploy.sh /
COPY opendatahub.yaml /
COPY prometheus.yaml /
COPY grafana.yaml /

RUN chmod 755 /deploy.sh && \
    chmod 644 /opendatahub.yaml && \
    chmod 644 /prometheus.yaml && \
    chmod 644 /grafana.yaml && \
    mkdir -p ${HOME} &&\
    chown 1001:0 ${HOME} &&\
    chmod ug+rwx ${HOME}

ARG builddate="(unknown)"
ARG version="(unknown)"
ARG vcs="(unknown)"

LABEL org.label-schema.build-date="${builddate}" \
      org.label-schema.description="Pod to deploy the CR for Open Data Hub" \
      org.label-schema.license="Apache-2.0" \
      org.label-schema.name="ODH deployer" \
      org.label-schema.vcs-ref="${vcs}" \
      org.label-schema.vendor="Red Hat" \
      org.label-schema.version="${version}"

ENTRYPOINT [ "/deploy.sh" ]

USER 1001
