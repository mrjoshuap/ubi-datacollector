# Copyright 2021 Lacework, Inc
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#

FROM registry.access.redhat.com/ubi8-minimal

MAINTAINER support@lacework.net

### Atomic/OpenShift Labels - https://github.com/projectatomic/ContainerApplicationGenericLabels
LABEL name="Lacework Agent" \
      maintainer="support@lacework.net" \
      vendor="Lacework" \
      version="4.3.0.5354" \
      release="1" \
      license="Apache-2.0" \
      summary="The Lacework Data Collection Agent" \
      description="Lacework is a continuous monitoring system that collects and monitors metadata of all the processes associated with a network activity." \
      vcs-url="https://github.com/mrjoshuap/ubi-datacollector.git" \
      vcs-ref="main" \
      vcs-type="git" \
      distribution-scope="restricted" \
      url="https://support.lacework.com/hc/en-us/articles/360005949293-Lacework-Agent-FAQs" \
      io.openshift.tags="lacework,security,monitoring" \
      io.openshift.non-scalable="true" \
      io.openshift.min-memory="512Mi" \
      io.openshift.min-cpu="0.1" \
      io.k8s.description="Lacework is a continuous monitoring system that collects and monitors metadata of all the processes associated with a network activity."

### add licenses to this directory
COPY licenses /licenses

USER root

COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY install.sh /usr/local/bin/install.sh

RUN /usr/local/bin/install.sh \
        && rm -f /var/lib/lacework/config/config.json

ENTRYPOINT ["/var/lib/lacework/datacollector"]
