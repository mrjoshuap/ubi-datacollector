FROM registry.access.redhat.com/ubi8-minimal

USER root

# uncomment to upgrade
# RUN microdnf update -y && rm -rf /var/cache/yum

COPY entry.sh /usr/local/bin/entry.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY install.sh /usr/local/bin/install.sh

RUN /usr/local/bin/install.sh \
        && rm -f /var/lib/lacework/config/config.json

ENTRYPOINT ["/usr/bin/local/entry.sh"]
