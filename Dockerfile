FROM registry.access.redhat.com/ubi8-minimal

ARG LACEWORK_ACCESS_TOKEN
ARG LACEWORK_SERVER_URL

RUN microdnf update -y && rm -rf /var/cache/yum

COPY install.sh /usr/local/bin/install.sh

USER root

RUN mkdir -p /var/lib/lacework/config \
        && touch /var/lib/lacework/config/config.json \
        && /usr/local/bin/install.sh "${LACEWORK_ACCESS_TOKEN:-'FICTIOUS-ACCESS-TOKEN'}" -U "${LACEWORK_SERVER_URL:-'https://fictional.lacework.net'}" \
        && rm -f /usr/local/bin/install.sh /var/lib/lacework/config/config.json

ENTRYPOINT ["/bin/sh","-c","/var/lib/lacework/datacollector"]
