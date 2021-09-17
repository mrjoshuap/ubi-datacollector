FROM registry.redhat.io/ubi8/ubi-minimal

ENV LACEWORK_ACCESS_TOKEN INVALID
ENV LACEWORK_SERVER_URL HTTPS://127.0.0.1/

COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/install.sh

RUN export LaceworkAccessToken=${LACEWORK_ACCESS_TOKEN} \
    && /usr/local/bin/install.sh -U "${LACEWORK_SERVER_URL}"

CMD /bin/bash
