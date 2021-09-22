FROM registry.access.redhat.com/ubi8-minimal

ARG LACEWORK_ACCESS_TOKEN
ARG LACEWORK_SERVER_URL

USER root

# uncomment to upgrade
# RUN microdnf update -y && rm -rf /var/cache/yum

COPY entry.sh /usr/local/bin/entry.sh
COPY install.sh /usr/local/bin/install.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN /usr/local/bin/install.sh \
        && rm -f /usr/local/bin/install.sh /var/lib/lacework/config/config.json

ENTRYPOINT ["/usr/bin/local/entry.sh"]
