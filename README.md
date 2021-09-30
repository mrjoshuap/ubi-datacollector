# ubi-datacollector

[![Docker Repository on Quay](https://quay.io/repository/themrjoshuap/ubi-datacollector/status "Docker Repository on Quay")](https://quay.io/repository/themrjoshuap/ubi-datacollector)

## About
This is the Lacework Agent Data Collector delivered as a UBI based image.  It is intended primarily to provide support for Kubernetes distributions that prefer UBI as compared to Alpine, chiefly OpenShift / OKD and Rancher.  Additionally, Red Hat support will strongly recommend you utilize UBI based images as they are able to provide support for mutual customers.

## Getting Started

The three ways I'm planning on testing:

1. OpenShift Code Ready Containers (CRC) -- All-In-One OpenShift for developer laptop use cases
2. OKD 4.7 on AWS - the open source distribution of OpenShift; is a minor version behind OCP
3. OCP 4.8 on AWS - using NFR subscriptions (when available)

### Setup Code Ready Containers
Note, the CRC is quite heavy.  If you need the monitoring and telemetry, as I do, expect to dedicate at least 14 GiB of memory (a value of 14336) for core functionality. Increased workloads will require more memory...

1. [Create a Red Hat Developer Account and download Code Ready Containers](https://developers.redhat.com/download-manager/link/3868678)
2. Download your pull secret and Code Ready Containers
3. Setup, configure and start Code Ready Containers
```
crc setup
crc config set cpus 6
crc config set disk-size 128
crc config set memory 24576 # 24 GB
crc config set kubeadmin-password 'lacework$'
crc config set consent-telemetry yes
crc config set enable-cluster-monitoring true
crc config set pull-secret-file /path/to/your/.crc_pull_secret.json
```

#### Start Code Ready Containers
```
crc start
eval $(crc oc-env)
```

#### Login as kubeadmin
```
oc login -u kubeadmin -p 'lacework$' https://api.crc.testing:6443
```

### Setup OCP4 / OKD4

#### Installation - OKD

1. Download the latest OpenShift Client CLI (don't worry about the installer)
2. Install the correct OKD installer using `oc`
3. You'll need AWS access and secret keys

NOTE: The OpenShift installer will also work on other deployments on-premise and cloud.

```
mkdir openshift-tools
cd openshift-tools
oc adm release extract --tools quay.io/openshift/okd:4.7.0-0.okd-2021-09-19-013247
tar -xzf openshift-install*.tar.gz
./openshift-install create cluster --log-level debug
```

#### Login as kubeadmin
```
oc login -u kubeadmin https://api.okd.laceworkdemo.com:6443
```

#### Configure SSL
```
cd $HOME
git clone https://github.com/neilpang/acme.sh

vi acme.sh/dnsapi/dns_aws.sh
egrep -e "^(AWS_ACCESS|AWS_SECRET)" acme.sh/dnsapi/dns_aws.sh

echo "Finding our OCP domains"
export LE_API=$(oc whoami --show-server | cut -f 2 -d ':' | cut -f 3 -d '/' | sed 's/-api././')
export LE_WILDCARD=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}')

echo "LE_API=$LE_API"
echo "LE_WILDCARD=$LE_WILDCARD"

echo "Registering new let's encrypt account"
./acme.sh/acme.sh --register-account -m joshua.preston@lacework.net

echo "Requesting certificate for $LE_API"
echo "Requesting certificate for $LE_WILDCARD"
./acme.sh/acme.sh --issue -d ${LE_API} -d "*.${LE_WILDCARD}" --dns dns_aws

echo "Retrieving certificates"
export CERTDIR=$HOME/certificates
mkdir -p ${CERTDIR}
./acme.sh/acme.sh --install-cert -d ${LE_API} -d "*.${LE_WILDCARD}" --cert-file ${CERTDIR}/cert.pem --key-file ${CERTDIR}/key.pem --fullchain-file ${CERTDIR}/fullchain.pem --ca-file ${CERTDIR}/ca.cer

echo "Installing certificates into OpenShift"
echo "NOTE: The certificate swap in OCP/OKD may take up to 30 minutes depending on cluster size"
oc create secret tls router-certs --cert=${CERTDIR}/fullchain.pem --key=${CERTDIR}/key.pem -n openshift-ingress
oc patch ingresscontroller default -n openshift-ingress-operator --type=merge --patch='{"spec": { "defaultCertificate": { "name": "router-certs" }}}'
oc create secret tls api-certs --cert=${CERTDIR}/fullchain.pem --key=${CERTDIR}/key.pem -n openshift-config
oc patch apiserver cluster --type merge --patch="{\"spec\": {\"servingCerts\": {\"namedCertificates\": [ { \"names\": [  \"$LE_API\"  ], \"servingCertificate\": {\"name\": \"api-certs\" }}]}}}"
```

#### Expose external registry and pull ubi-datacollector image
```
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
podman login -u $(oc whoami) -p $(oc whoami -t) $HOST
podman pull $HOST/lacework/ubi-datacollector
```

## Install Lacework Agent Data Collector
```
oc new-project lacework --display-name="Lacework" --description="Project and namespace for the Lacework Data Collector Agent"

oc create serviceaccount lacework -n lacework

oc adm policy add-scc-to-user privileged -z lacework

oc import-image registry.access.redhat.com/ubi8-minimal:latest --from=registry.access.redhat.com/ubi8-minimal:latest --scheduled --confirm

#oc import-image lacework/ubi-datacollector:latest --from=quay.io/themrjoshuap/ubi-datacollector:latest --scheduled --confirm

oc new-build https://github.com/mrjoshuap/ubi-datacollector.git\#main --strategy=docker --to=lacework/datacollector-ubi8:latest
oc set triggers bc/ubi-datacollector --auto
oc set triggers bc/ubi-datacollector --from-image="lacework/ubi8-minimal:latest"

cp example_config.json config.json
vi config.json

oc create configmap lacework-config --from-file=config.json=config.json

oc create -n lacework -f lacework-k8s.yaml

oc set image-lookup --all
oc set image-lookup daemonset/lacework-agent

oc set triggers ds/lacework-agent --auto
oc set triggers ds/lacework-agent --from-image='lacework/datacollector-ubi8:latest' --containers="datacollector" 

oc get all -n lacework

oc start-build ubi-datacollector --follow
oc set image ds/lacework-agent datacollector=lacework/datacollector-ubi8:latest

curl -X POST https://api.ocp4.laceworkdemo.com:6443/apis/build.openshift.io/v1/namespaces/lacework/buildconfigs/ubi-datacollector/webhooks/r8a7Uq9mgzTkFS1GG_NC/generic

curl -H "X-GitHub-Event: push" -H "Content-Type: application/json" -X POST --data-binary @payload.json https://api.ocp4.laceworkdemo.com:6443/apis/build.openshift.io/v1/namespaces/lacework/buildconfigs/ubi-datacollector/webhooks/FO_i2s7aSgdXgxNhnKn5/github
```

## To Do ... Notes ... Wish List

* Build an operator
* Add to operator hub and red hat marketplace
* Test the managed services versions?
* Fix vulnerability scans -- they show as "unsupported" or something like that
* Move ubi image into lacework proper repository (or create one in quay.io)
* no more logs -- need to use stdout -- see entry.sh
* vuln scanning seems not to work with Red Hat Linux CoreOS (yes, i know)
* need proper healthchecks -- see healthcheck.sh
* update agent install / service for podman
* need to incorporate installation with other build processes -- see install.sh
* need to expose the internal registry and test container scanning
* buildconfigs need to specify the ref if not using a "master" branch -- ie main is default
* need to build an arm64 / aarch64 container image

## License and Copyright

Copyright 2020, Lacework Inc.

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
