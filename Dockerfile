FROM registry.redhat.io/ubi8/ubi-minimal

COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/install.sh

RUN mkdir -p /var/lib/lacework/config/ \
    && touch /var/lib/lacework/config/config.json \
    && /usr/local/bin/install.sh \
    && rm /var/lib/lacework/config/config.json

CMD /bin/bash
