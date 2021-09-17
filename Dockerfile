FROM registry.redhat.io/ubi8/ubi-minimal

ENV DATACOLLECTOR_VERSION=4.3.0.5146
ENV DATACOLLECTOR_COMMIT_HASH=4.3.0.5146_2021-09-13_master_36599af652b771c16f9e64f4cc3bf5d6ea8fe3b0
ENV DATACOLLECTOR_PKG_FULLNAME="${pkgname}-${version}-1.${rpm_pkg_suffix}.rpm"

RUN cd /tmp \
  && curl -OsSL https://s3-us-west-2.amazonaws.com/www.lacework.net/download/${DATACOLLECTOR_COMMIT_HASH}/install.sh \
  && chmod +x /tmp/install.sh \
  && /tmp/install.sh

