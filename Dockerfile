FROM registry.access.redhat.com/ubi8/ubi-minimal

ENV LACEWORK_ACCESS_TOKEN FICTIONAL-ACCESS-TOKEN
ENV LACEWORK_SERVER_URL https://fictional.lacework.net

# RUN microdnf update -y && rm -rf /var/cache/yum

COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/install.sh

RUN /usr/local/bin/install.sh "${LACEWORK_ACCESS_TOKEN}" -U "${LACEWORK_SERVER_URL}"

USER root

CMD "/var/lib/lacework/datacollector ${LWDC_OPTS}"
