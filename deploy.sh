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


# This functino is used to get the value of certain secrets/tokens
# as part of the monitoring deployment process

function oc::wait::object::availability() {
    local cmd=$1 # Command whose output we require
    local interval=$2 # How many seconds to sleep between tries
    local iterations=$3 # How many times we attempt to run the command

    ii=0

    while [ $ii -le $iterations ]
    do

        token=$($cmd) && returncode=$? || returncode=$?
        if [ $returncode -eq 0 ]; then
            break
        fi

        ((ii=ii+1))
        if [ $ii -eq 100 ]; then
            echo $cmd "did not return a value"
            exit 1
        fi
        sleep $interval
    done
    echo $token
}


ODH_PROJECT=${ODH_CR_NAMESPACE:-"redhat-ods-applications"}
ODH_MONITORING_PROJECT=${ODH_MONITORING_NAMESPACE:-"redhat-ods-monitoring"}
oc new-project ${ODH_PROJECT} || echo "INFO: ${ODH_PROJECT} project already exists."

# If a reader secret has been created, link it to the default SA
# This is so that private images in quay.io/modh can be loaded into imagestreams
READER_SECRET="addon-managed-odh-pullsecret"
linkdefault=0
oc get secret ${READER_SECRET} &> /dev/null || linkdefault=1
if [ "$linkdefault" -eq 0 ]; then
    echo Linking ${READER_SECRET} to default SA
    oc secret link default ${READER_SECRET} --for=pull -n ${ODH_PROJECT}
else
    echo no ${READER_SECRET} secret, default SA unchanged
fi

export jupyterhub_prometheus_api_token=$(openssl rand -hex 32)
sed -i "s/<jupyterhub_prometheus_api_token>/$jupyterhub_prometheus_api_token/g" monitoring/jupyterhub-prometheus-token-secrets.yaml
oc apply -n ${ODH_PROJECT} -f monitoring/jupyterhub-prometheus-token-secrets.yaml

oc apply -n ${ODH_PROJECT} -f opendatahub.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the ODH CR failed."
  exit 1
fi

oc new-project $ODH_MONITORING_PROJECT || echo "INFO: $ODH_MONITORING_PROJECT project already exists."
oc label namespace $ODH_MONITORING_PROJECT openshift.io/cluster-monitoring=true --overwrite=true
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/cluster-monitoring/cluster-monitor-rbac.yaml

sed -i "s/<prometheus_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/prometheus/prometheus-secrets.yaml
sed -i "s/<alertmanager_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/prometheus/prometheus-secrets.yaml
oc create -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus-secrets.yaml || echo "INFO: Prometheus session secrets already exist."


prometheus_token=$(oc::wait::object::availability "oc sa -n $ODH_MONITORING_PROJECT get-token prometheus" 2 30)
ocp_federate_target=$(oc::wait::object::availability "oc get -n openshift-monitoring route prometheus-k8s -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")

sed -i "s/<jupyterhub_prometheus_api_token>/$jupyterhub_prometheus_api_token/g" monitoring/prometheus/prometheus.yaml
sed -i "s/<prom_bearer_token>/$prometheus_token/g" monitoring/prometheus/prometheus.yaml
sed -i "s/<federate_target>/$ocp_federate_target/g" monitoring/prometheus/prometheus.yaml
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/alertmanager-svc.yaml

alertmanager_host=$(oc::wait::object::availability "oc get route alertmanager -n $ODH_MONITORING_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
pagerduty_service_token=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT -o jsonpath='{.data.PAGERDUTY_KEY}'" 5 120)

oc apply -f monitoring/jupyterhub-route.yaml -n $ODH_PROJECT
oc apply -f monitoring/rhods-dashboard-route.yaml -n $ODH_PROJECT

jupyterhub_host=$(oc::wait::object::availability "oc get route jupyterhub -n $ODH_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
rhods_dashboard_host=$(oc::wait::object::availability "oc get route odh-dashboard -n $ODH_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")

sed -i "s/<jupyterhub_host>/$jupyterhub_host/g" monitoring/prometheus/prometheus.yaml
sed -i "s/<rhods_dashboard_host>/$rhods_dashboard_host/g" monitoring/prometheus/prometheus.yaml
sed -i "s/<pagerduty_token>/$pagerduty_service_token/g" monitoring/prometheus/prometheus.yaml
sed -i "s/<set_alertmanager_host>/$alertmanager_host/g" monitoring/prometheus/prometheus.yaml


oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/blackbox-exporter-common.yaml

if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"redhat.com".* ]]
then
  oc apply -f monitoring/prometheus/blackbox-exporter-internal.yaml -n $ODH_MONITORING_PROJECT
else
  oc apply -f monitoring/prometheus/blackbox-exporter-external.yaml -n $ODH_MONITORING_PROJECT
fi

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus.yaml
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana-sa.yaml

prometheus_route=$(oc::wait::object::availability "oc get route prometheus -n $ODH_MONITORING_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
grafana_token=$(oc::wait::object::availability "oc sa get-token grafana -n $ODH_MONITORING_PROJECT" 2 30)

sed -i "s/<change_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/grafana/grafana-secrets.yaml
sed -i "s/<change_route>/$prometheus_route/g" monitoring/grafana/grafana-secrets.yaml
sed -i "s/<change_token>/$grafana_token/g" monitoring/grafana/grafana-secrets.yaml

oc create -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana-secrets.yaml || echo "INFO: Grafana secrets already exist."

oc::wait::object::availability "oc get secret grafana-config -n $ODH_MONITORING_PROJECT" 2 30
oc::wait::object::availability "oc get secret grafana-proxy-config -n $ODH_MONITORING_PROJECT" 2 30
oc::wait::object::availability "oc get secret grafana-datasources -n $ODH_MONITORING_PROJECT" 2 30

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana-dashboards
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/cluster-monitoring/rhods-rules.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/jupyterhub-db-probe/jupyterhub-db-probe.yaml

# Add consoleLink CR to provide a link to the odh-dashboard via the Application Launcher in OpenShift
cluster_domain=$(oc get ingresses.config.openshift.io cluster --template {{.spec.domain}})
odh_dashboard_route="https://odh-dashboard-$ODH_PROJECT.$cluster_domain"
sed -i "s#<rhods-dashboard-url>#$odh_dashboard_route#g" consolelink/consolelink.yaml
oc apply -f consolelink/consolelink.yaml
