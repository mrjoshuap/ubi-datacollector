FROM registry.access.redhat.com/ubi8-minimal

ARG LACEWORK_ACCESS_TOKEN
ARG LACEWORK_SERVER_URL

RUN microdnf update -y && rm -rf /var/cache/yum

COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/install.sh \
        && /usr/local/bin/install.sh "${LACEWORK_ACCESS_TOKEN}" -U "${LACEWORK_SERVER_URL}" \
        && rm -f /usr/local/bin/install.sh

USER root

ENTRYPOINT ["/bin/sh","-c","/var/lib/lacework/datacollector"]
