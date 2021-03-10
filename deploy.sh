#! /bin/bash

# Copyright 2020 Red Hat, Inc. and/or its affiliates.
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

set -e -o pipefail

ODH_PROJECT=${ODH_CR_NAMESPACE:-"redhat-ods-applications"}
ODH_MONITORING_PROJECT=${ODH_MONITORING_NAMESPACE:-"redhat-ods-monitoring"}
oc new-project ${ODH_PROJECT} || echo "INFO: ${ODH_PROJECT} project already exists."

oc apply -n ${ODH_PROJECT} -f opendatahub.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the ODH CR failed."
  exit 1
fi

oc new-project $ODH_MONITORING_PROJECT || echo "INFO: $ODH_MONITORING_PROJECT project already exists."
oc label namespace $ODH_MONITORING_PROJECT openshift.io/cluster-monitoring=true --overwrite=true
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/cluster-monitoring/cluster-monitor-rbac.yaml

sed -i "s/<prometheus_proxy_secret>/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/g" monitoring/prometheus/prometheus-secrets.yaml
sed -i "s/<alertmanager_proxy_secret>/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/g" monitoring/prometheus/prometheus-secrets.yaml
oc create -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus-secrets.yaml || echo "INFO: Prometheus session secrets already exist."
sleep 5
sed -i "s/<prom_bearer_token>/$(oc sa -n $ODH_MONITORING_PROJECT get-token prometheus)/g" monitoring/prometheus/prometheus.yaml
sed -i "s/<federate_target>/$(oc get -n openshift-monitoring route prometheus-k8s -o jsonpath='{.spec.host}')/g" monitoring/prometheus/prometheus.yaml
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/alertmanager-svc.yaml
sed -i "s/<set_alertmanager_host>/$(oc get route alertmanager -o jsonpath='{.spec.host}')/g" monitoring/prometheus/prometheus.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus.yaml

oc apply -f monitoring/grafana/grafana-sa.yaml

sed -i "s/<change_proxy_secret>/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/g" monitoring/grafana/grafana-secrets.yaml
sed -i "s/<change_route>/$(oc get route prometheus -o jsonpath='{.spec.host}')/g" monitoring/grafana/grafana-secrets.yaml
sed -i "s/<change_token>/$(oc sa get-token grafana)/g" monitoring/grafana/grafana-secrets.yaml
oc create -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana-secrets.yaml || echo "INFO: Grafana secrets already exist."
sleep 5
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana-dashboards
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/cluster-monitoring/rhods-rules.yaml
