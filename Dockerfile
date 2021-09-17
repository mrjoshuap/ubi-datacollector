FROM registry.redhat.io/ubi8/ubi-minimal

COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/install.sh

RUN /usr/local/bin/install.sh

CMD /bin/bash
