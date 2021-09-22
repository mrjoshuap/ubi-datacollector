# ubi-datacollector

[![Docker Repository on Quay](https://quay.io/repository/themrjoshuap/ubi-datacollector/status "Docker Repository on Quay")](https://quay.io/repository/themrjoshuap/ubi-datacollector)

## About
This is the Lacework Agent Data Collector delivered as a UBI based image.  It is intended primarily to provide support for Kubernetes distributions that prefer UBI as compared to Alpine, chiefly OpenShift / OKD and Rancher.  Additionally, Red Hat certification will strongly recommend we utilize UBI based images as they are able to provide mutual support.

## Getting Started

Note, the CRC is quite heavy.  If you need the monitoring and telemetry, as I do, expect to dedicate at least 14 GiB of memory (a value of 14336) for core functionality. Increased workloads will require more memory...

### Setup Code Ready Containers
1. Create a Red Hat Developer Account
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

### Start Code Ready Containers
```
crc start
eval $(crc oc-env)
```

### Login as kubeadmin
```
oc login -u kubeadmin -p 'lacework$' https://api.crc.testing:6443
```

### Login as developer
```
oc login -u developer -p 'developer' https://api.crc.testing:6443
```

### TODO:
```
oc new-project lacework --display-name="Lacework" --description="Project and namespace for the Lacework Data Collector Agent"

oc create serviceaccount lacework -n lacework

oc adm policy add-scc-to-user privileged -z lacework

oc import-image registry.access.redhat.com/ubi8-minimal --from=registry.access.redhat.com/ubi8-minimal:latest --scheduled

#oc import-image ubi-datacollector --from=quay.io/themrjoshuap/ubi-datacollector:latest -n lacework --confirm

cp example_config.json config.json
vi config.json

oc create configmap lacework-config --from-file=config.json=config.json

oc new-build https://github.com/mrjoshuap/ubi-datacollector.git --strategy=docker --to ubi-datacollector
oc set triggers bc ubi-datacollector --from-image="ubi8-minimal:latest"
oc set triggers bc ubi-datacollector --from-config

oc create -n lacework -f lacework-k8s.yaml

oc set image-lookup daemonset/lacework-agent
oc set triggers ds lacework-agent --containers="datacollector" --from-image='lacework/ubi-datacollector:latest'

oc get all -n lacework
```

## To Do ... Wish List

* Build an operator
