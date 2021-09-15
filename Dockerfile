FROM registry.redhat.io/ubi8/ubi-minimal

RUN curl -sSL https://s3-us-west-2.amazonaws.com/www.lacework.net/download/4.3.0.5146_2021-09-13_master_36599af652b771c16f9e64f4cc3bf5d6ea8fe3b0/install.sh > /tmp/install.sh
RUN chmod +x /tmp/install.sh
RUN /tmp/install.sh
