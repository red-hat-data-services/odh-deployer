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


# This function is used to get the value of certain secrets/tokens
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

function oc::object::safe::to::apply() {
  local kind=$1
  local resource=$2
  local label="opendatahub.io/modified=false"

  local object="${kind}/${resource}"

  exists=$(oc get -n $ODH_PROJECT ${object} -o name | grep ${object} || echo "false")
  original=$(oc get -n $ODH_PROJECT ${kind} -l ${label} -o name | grep ${object} || echo "false")
  if [ "$exists" == "false" ]; then
    return 0
  fi

  if [ "$original" == "false" ]; then
    return 1
  fi

  return 0
}


ODH_PROJECT=${ODH_CR_NAMESPACE:-"redhat-ods-applications"}
ODH_MONITORING_PROJECT=${ODH_MONITORING_NAMESPACE:-"redhat-ods-monitoring"}
ODH_NOTEBOOK_PROJECT=${ODH_NOTEBOOK_NAMESPACE:-"rhods-notebooks"}
CRO_PROJECT=${CRO_NAMESPACE:-"redhat-ods-operator"}
ODH_OPERATOR_PROJECT=${OPERATOR_NAMESPACE:-"redhat-ods-operator"}
NAMESPACE_LABEL="opendatahub.io/generated-namespace=true"

oc new-project ${ODH_PROJECT} || echo "INFO: ${ODH_PROJECT} project already exists."
oc label namespace $ODH_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."

oc new-project ${ODH_NOTEBOOK_PROJECT} || echo "INFO: ${ODH_NOTEBOOK_PROJECT} project already exists."
oc label namespace $ODH_NOTEBOOK_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."

oc new-project $ODH_MONITORING_PROJECT || echo "INFO: $ODH_MONITORING_PROJECT project already exists."
oc label namespace $ODH_MONITORING_PROJECT openshift.io/cluster-monitoring=true --overwrite=true
oc label namespace $ODH_MONITORING_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."

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
oc create -n ${ODH_PROJECT} -f monitoring/jupyterhub-prometheus-token-secrets.yaml || echo "INFO: Jupyterhub scrape token already exist."

sed -i "s/<notebook_destination>/$ODH_NOTEBOOK_PROJECT/g" jupyterhub/jupyterhub-configmap.yaml
# Requires oc create instead of apply to prevent overwriting.
oc create -n ${ODH_PROJECT} -f jupyterhub/jupyterhub-configmap.yaml || echo "INFO: Jupyterhub ConfigMap already created "

infrastructure=$(oc get infrastructure cluster -o jsonpath='{.spec.platformSpec.type}')
# Check if the installation target is AWS to determine the deployment manifest path
if [ $infrastructure = "AWS" ]; then
  # On AWS OpenShift Dedicated, deploy with CRO
  echo "INFO: Deploying on AWS. Creating CRO for deployment of RDS Instance"
  ODH_MANIFESTS="opendatahub-osd.yaml"

  # Install CRO
  oc new-project ${CRO_PROJECT} || echo "INFO: ${CRO_PROJECT} project already exists."
  oc label namespace $CRO_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."
  oc apply -n ${ODH_PROJECT} -f cloud-resource-operator/crds
  oc apply -n ${ODH_PROJECT} -f cloud-resource-operator/rbac
  oc apply -n ${CRO_PROJECT} -f cloud-resource-operator/rbac-rds
  oc apply -n ${CRO_PROJECT} -f cloud-resource-operator/deployment
  oc apply -n ${ODH_PROJECT} -f cloud-resource-operator/postgres.yaml

  jupyterhubsecret=$(oc::wait::object::availability "oc get secret jupyterhub-rds-secret -n $ODH_PROJECT" 30 60)
  if [ -z "$jupyterhubsecret" ];then
    echo "ERROR: Jupyterhub RDS secret does not exist."
    exit 1
  fi


  sed -i '/tlsSkipVerify/d' monitoring/grafana/grafana-secrets.yaml

  # Give dedicated-admins group CRUD access to ConfigMaps, Secrets, ImageStreams, Builds and BuildConfigs in select namespaces
  for target_project in ${ODH_PROJECT} ${ODH_NOTEBOOK_PROJECT}; do
    oc apply -n $target_project -f rhods-osd-configs.yaml
    if [ $? -ne 0 ]; then
      echo "ERROR: Attempt to create the RBAC policy for dedicated admins group in $target_project failed."
      exit 1
    fi
  done
elif [ $infrastructure = "OpenStack" ]; then
  # On PSI, deploy local
  echo "INFO: Deploying on PSI. Creating local database"
  ODH_MANIFESTS="opendatahub.yaml"

  # Create Postgres Secret
  export jupyterhub_postgresql_password=$(openssl rand -hex 32)
  sed -i "s/<jupyterhub_postgresql_password>/$jupyterhub_postgresql_password/g" jupyterhub/jupyterhub-database-password.yaml
  oc create -n ${ODH_PROJECT} -f jupyterhub/jupyterhub-database-password.yaml || echo "INFO: Jupyterhub Password already exist."
else
  # Not on PSI or AWS, Fail Installation
  echo "ERROR: Deploying on $infrastructure, which is not supported. Failing Installation"
  exit 1
fi

oc apply -n ${ODH_PROJECT} -f rhods-dashboard.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the Dashboard CR failed."
  exit 1
fi

oc apply -n ${ODH_PROJECT} -f ${ODH_MANIFESTS}
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the JupyterHub CR failed."
  exit 1
fi

oc apply -n ${ODH_NOTEBOOK_PROJECT} -f rhods-notebooks.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the RHODS Notebooks CR failed."
  exit 1
fi

oc apply -n ${ODH_PROJECT} -f rhods-anaconda.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the anaconda CR failed."
  exit 1
fi

oc apply -n ${ODH_PROJECT} -f rhods-nbc.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the Notebook Controller CR failed."
  exit 1
fi

deadmanssnitch=$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-deadmanssnitch -o jsonpath='{.data.SNITCH_URL}'" 4 90 | tr -d "'"  | base64 --decode)

if [ -z "$deadmanssnitch" ];then
    echo "ERROR: Dead Man Snitch secret does not exist."
    exit 1
fi

sed -i "s#<snitch_url>#$deadmanssnitch#g" monitoring/prometheus/prometheus-configs.yaml

oc apply -n ${ODH_MONITORING_PROJECT} -f rhods-monitoring.yaml

sed -i "s/<prometheus_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/prometheus/prometheus-secrets.yaml
sed -i "s/<alertmanager_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/prometheus/prometheus-secrets.yaml
oc create -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus-secrets.yaml || echo "INFO: Prometheus session secrets already exist."


sed -i "s/<jupyterhub_prometheus_api_token>/$(oc::wait::object::availability "oc get secret -n $ODH_PROJECT jupyterhub-prometheus-token-secrets -o jsonpath='{.data.PROMETHEUS_API_TOKEN}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/alertmanager-svc.yaml

alertmanager_host=$(oc::wait::object::availability "oc get route alertmanager -n $ODH_MONITORING_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")

# Check if pagerduty secret exists, if not, exit installation

redhat_rhods_pagerduty=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT" 5 60 )

if [ -z "$redhat_rhods_pagerduty" ];then
    echo "ERROR: Pagerduty secret does not exist."
    exit 1
fi

pagerduty_service_token=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT -o jsonpath='{.data.PAGERDUTY_KEY}'" 5 10)
pagerduty_service_token=$(echo -ne "$pagerduty_service_token" | tr -d "'" | base64 --decode)

oc apply -f monitoring/jupyterhub-route.yaml -n $ODH_PROJECT
oc apply -f monitoring/rhods-dashboard-route.yaml -n $ODH_PROJECT

jupyterhub_host=$(oc::wait::object::availability "oc get route jupyterhub -n $ODH_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
rhods_dashboard_host=$(oc::wait::object::availability "oc get route rhods-dashboard -n $ODH_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")

sed -i "s/<jupyterhub_host>/$jupyterhub_host/g" monitoring/prometheus/prometheus-configs.yaml
sed -i "s/<rhods_dashboard_host>/$rhods_dashboard_host/g" monitoring/prometheus/prometheus-configs.yaml
sed -i "s/<pagerduty_token>/$pagerduty_service_token/g" monitoring/prometheus/prometheus-configs.yaml
sed -i "s/<set_alertmanager_host>/$alertmanager_host/g" monitoring/prometheus/prometheus.yaml

# Check if smtp secret exists, exit if it doesn't
redhat_rhods_smtp=$(oc::wait::object::availability "oc get secret redhat-rhods-smtp -n $ODH_MONITORING_PROJECT" 5 60 )

if [ -z "$redhat_rhods_smtp" ];then
    echo "ERROR: SMTP secret does not exist."
    exit 1
fi

# Check if addon parameter for mail secret exists, exit if it doesn't

addon_managed_odh_parameter=$(oc::wait::object::availability "oc get secret addon-managed-odh-parameters -n $ODH_OPERATOR_PROJECT" 5 60 )

if [ -z "$addon_managed_odh_parameter" ];then
    echo "ERROR: Addon managed odh parameter secret does not exist."
    exit 1
fi

sed -i "s/<smtp_host>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.host}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
sed -i "s/<smtp_port>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.port}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
sed -i "s/<smtp_username>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.username}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
sed -i "s/<smtp_password>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.password}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml

sed -i "s/<user_emails>/$(oc::wait::object::availability "oc get secret -n $ODH_OPERATOR_PROJECT addon-managed-odh-parameters -o jsonpath='{.data.notification-email}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/blackbox-exporter-common.yaml

if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"redhat.com".* ]]
then
  oc apply -f monitoring/prometheus/blackbox-exporter-internal.yaml -n $ODH_MONITORING_PROJECT
else
  oc apply -f monitoring/prometheus/blackbox-exporter-external.yaml -n $ODH_MONITORING_PROJECT
fi

if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"devshift.org".* ]]
then
  sed -i "s/redhat-openshift-alert@devshift.net/redhat-openshift-alert@rhmw.io/g" monitoring/prometheus/prometheus-configs.yaml
fi

if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"aisrhods".* ]]
then
  echo "Cluster is for RHODS engineering or test purposes. Disabling SRE alerting."
  sed -i "s/receiver: PagerDuty/receiver: alerts-sink/g" monitoring/prometheus/prometheus-configs.yaml
else
  echo "Cluster is not for RHODS engineering or test purposes."
fi

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus-configs.yaml

prometheus_config=$(oc get cm prometheus -n $ODH_MONITORING_PROJECT -o jsonpath='{.data}' | openssl dgst -binary -sha256 | openssl base64)
alertmanager_config=$(oc get cm alertmanager -n $ODH_MONITORING_PROJECT -o jsonpath='{.data.alertmanager\.yml}' | openssl dgst -binary -sha256 | openssl base64)

sed -i "s#<prometheus_config_hash>#$prometheus_config#g" monitoring/prometheus/prometheus.yaml
sed -i "s#<alertmanager_config_hash>#$alertmanager_config#g" monitoring/prometheus/prometheus.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus.yaml
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana-sa.yaml


prometheus_route=$(oc::wait::object::availability "oc get route prometheus -n $ODH_MONITORING_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
grafana_token=$(oc::wait::object::availability "oc sa get-token grafana -n $ODH_MONITORING_PROJECT" 2 30)
grafana_proxy_secret=$(oc get -n $ODH_MONITORING_PROJECT secret grafana-proxy-config -o jsonpath='{.data.session_secret}') && returncode=$? || returncode=$?

if [[ $returncode == 0 ]]
then
    echo "INFO: Grafana secrets already exist"
    grafana_proxy_secret_token=$(echo $grafana_proxy_secret | base64 --decode)
else
    echo "INFO: Grafana secrets did not exist. Generating new proxy token"
    grafana_proxy_secret_token=$(openssl rand -hex 32)
fi
sed -i "s/<change_proxy_secret>/$grafana_proxy_secret_token/g" monitoring/grafana/grafana-secrets.yaml
sed -i "s/<change_route>/$prometheus_route/g" monitoring/grafana/grafana-secrets.yaml
sed -i "s/<change_token>/$grafana_token/g" monitoring/grafana/grafana-secrets.yaml

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana-secrets.yaml

oc::wait::object::availability "oc get secret grafana-config -n $ODH_MONITORING_PROJECT" 2 30
oc::wait::object::availability "oc get secret grafana-proxy-config -n $ODH_MONITORING_PROJECT" 2 30
oc::wait::object::availability "oc get secret grafana-datasources -n $ODH_MONITORING_PROJECT" 2 30

oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana-dashboards
oc apply -n $ODH_MONITORING_PROJECT -f monitoring/grafana/grafana.yaml

# Add segment.io secret key & configmap
oc apply -n ${ODH_PROJECT} -f monitoring/segment-key-secret.yaml
oc apply -n ${ODH_PROJECT} -f monitoring/segment-key-config.yaml

# Add consoleLink CR to provide a link to the rhods-dashboard via the Application Launcher in OpenShift
cluster_domain=$(oc get ingresses.config.openshift.io cluster --template {{.spec.domain}})
odh_dashboard_route="https://rhods-dashboard-$ODH_PROJECT.$cluster_domain"
sed -i "s#<rhods-dashboard-url>#$odh_dashboard_route#g" consolelink/consolelink.yaml
oc apply -f consolelink/consolelink.yaml

kind="configmap"
resource="odh-jupyterhub-global-profile"

if oc::object::safe::to::apply ${kind} ${resource}; then
  oc apply -n ${ODH_PROJECT} -f jupyterhub/jupyterhub-singleuser-profiles-global-profile-configmap.yaml
else
  echo "The JH singleuser global profile ConfigMap (${kind}/${resource}) has been modified. Skipping apply."
fi

kind="configmap"
resource="rhods-jupyterhub-sizes"

if oc::object::safe::to::apply ${kind} ${resource}; then
  oc apply -n ${ODH_PROJECT} -f jupyterhub/sizes/jupyterhub-singleuser-profiles-sizes-configmap.yaml
else
  echo "The sizes ConfigMap (${kind}/${resource}) has been modified. Skipping apply."
fi

kind="configmap"
resource="rhods-groups-config"
object="rhods-groups-config"
exists=$(oc get -n $ODH_PROJECT ${kind} ${object} -o name | grep ${object} || echo "false")
# If this is a pre-existing cluster (ie: we are upgrading), then we will not touch the groups configmap
# This is part of RHODS-2442 where we are changing the default groups.  The idea is for it to
# not affect any pre-exisitng clusters that have already set up their access as they see fit.
if [ "$exists" == "false" ]; then
  if oc::object::safe::to::apply ${kind} ${resource}; then
    oc apply -n ${ODH_PROJECT} -f groups/groups.configmap.yaml
  else
    echo "The groups ConfigMap (${kind}/${resource}) has been modified. Skipping apply."
  fi
fi

kind="secret"
resource="anaconda-ce-access"

if oc::object::safe::to::apply ${kind} ${resource}; then
  oc apply -n ${ODH_PROJECT} -f partners/anaconda/anaconda-ce-access.yaml
else
  echo "The Anaconda base secret (${kind}/${resource}) has been modified. Skipping apply."
fi

####################################################################################################
# RHODS DASHBOARD
####################################################################################################

# Deploying the ODHDashboardConfig CRD
oc apply -n ${ODH_PROJECT} -f odh-dashboard/crds/odh-dashboard-crd.yaml
odhdashboardconfigcrd=$(oc::wait::object::availability "oc get crd odhdashboardconfigs.opendatahub.io" 30 60)
if [ -z "$odhdashboardconfigcrd" ];then
  echo "ERROR: OdhDashboardConfig CRD does not exist."
  exit 1
fi

kind="configmap"
resource="odh-enabled-applications-config"
object="odh-enabled-applications-config"
exists=$(oc get -n $ODH_PROJECT ${kind} ${object} -o name | grep ${object} || echo "false")
#TODO: This should probably exist in odh-manifests due to the fact that it controls enabled applications
if [ "$exists" == "false" ]; then
  if oc::object::safe::to::apply ${kind} ${resource}; then
    oc apply -n ${ODH_PROJECT} -f odh-dashboard/configs/odh-enabled-applications-config.configmap.yaml
  else
    echo "The ODH Dashboard enabled-applications-config (${kind}/${resource}) has been modified. Skipping apply."
  fi
fi

kind="odhdashboardconfigs"
resource="odh-dashboard-config"
object="odh-dashboard-config"
exists=$(oc get -n $ODH_PROJECT ${kind} ${object} -o name | grep ${object} || echo "false")
# If this is a pre-existing cluster (ie: we are upgrading), then we will not touch the ODHDashboardConfig resource
#TODO: This controls feature flags and notebook controller presets like Notebook size. Confirm that notebook sizes can be configured external to the ODHDashboardConfig CR
if [ "$exists" == "false" ]; then
  if oc::object::safe::to::apply ${kind} ${resource}; then
    oc apply -n ${ODH_PROJECT} -f odh-dashboard/configs/odh-dashboard-config.yaml
  else
    echo "The ODHDashboardConfig (${kind}/${resource}) has been modified. Skipping apply."
  fi
fi

####################################################################################################
# END RHODS DASHBOARD
####################################################################################################

# Add network policies
oc apply -f network/

# Create the runtime buildchain if the rhods-buildchain configmap is missing,
# otherwise recreate it if the stored hecksum does not match
$HOME/buildchain.sh
