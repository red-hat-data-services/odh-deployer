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


# Get the value of certain resources with interation
#
# Arguments:
#   $1: external command
#   $2: interval by seconds
#   $3: iterate times
#
# Returns:
#   0 if the file exists, 1 otherwise
function oc::wait::object::availability() {
    local cmd="$1"        # Command whose output we require
    local interval="$2"   # How many seconds to sleep between tries
    local iterations="$3" # How many times we attempt to run the command
    ii=0

    while [ "$ii" -le "$iterations" ]
    do
        output="$($cmd)" # Run the command and capture its output
        returncode=$? # Capture the return code of the command

        [ $returncode -eq 0 ] && break

        if [[ "$ii" -eq 100 ]]; then
            echo "$cmd did not return a value"
            exit 1
        fi

        sleep "$interval"
        ((ii++))
    done

    echo "$output"
}

# Create ISV CRD for Dashboard then apply self-managed and managed service ISV
#
# Arguments:
#   $1: namespace where CRD applied to
#
function oc::dashboard::apply::isvs() {
  local namespace="$1"        # Command whose output we require

  local crd_arr=(
    "odhapplications.dashboard.opendatahub.io"
    "odhdocuments.dashboard.opendatahub.io"
    "odhquickstarts.console.openshift.io"
  )

  oc apply -n "$namespace" -k odh-dashboard/crds
  for crd_name in "${crd_arr[@]}"
  do
    dashboard_crd=$(oc::wait::object::availability "oc get crd $crd_name" 30 60)
    if [[ -z "$dashboard_crd" ]];then
      echo "ERROR: $crd_name CRD does not exist."
      exit 1
    fi
  done

  # Embedding the command in the IF statement since bash SHELLOPT "errexit" is enabled
  # and the script will exit immediately when this command fails

  # apply resource from dashboard depends on different installation env.
  if [[ "$RHODS_SELF_MANAGED" -eq 0 ]]; then
    oc apply -n "$namespace" -k odh-dashboard/apps-managed-service
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Attempt to install the Dashaboard ISVs application tiles for managed services failed"
      exit 1
    fi
  else
    oc apply -n ${ODH_PROJECT} -k odh-dashboard/apps-on-prem
    if [ $? -ne 0 ]; then
      echo "ERROR: Attempt to install the Dashboard ISVs application tiles for self-managed services failed"
      exit 1
    fi
  fi
}

# Check source exist or has been modified
#
# Arguments:
#   $1: kind      kind in k8s
#   $2: resource  resource type in k8s
#   $3: label     label to filter
#
# Return:
#   2:  exist but no label modified=false
#   1:  modified=false
#   0:  does not exist kind/resource at all
function oc::object::safe::to::apply() {
  local kind=$1
  local resource=$2
  local label=${3:-opendatahub.io/modified=false}

  local object="$kind/$resource"
  exists=$(oc get "$object" -n "$ODH_PROJECT" -o name | grep "$object" || echo "false")
  if [[ "$exists" == "false" ]]; then
    echo "0"
    exit 0
  fi

  original=$(oc get -n $ODH_PROJECT $kind -l "$label" -o name | grep "$object" || echo "false")
  if [[ "$original" == "false" ]]; then
    echo "1"
    return 1
  fi

  echo "2"
  return 0
}

##############################
## define all env variables
##############################

## define namespace variables
ODH_PROJECT=${ODH_CR_NAMESPACE:-"redhat-ods-applications"}
ODH_MONITORING_PROJECT=${ODH_MONITORING_NAMESPACE:-"redhat-ods-monitoring"}
ODH_NOTEBOOK_PROJECT=${ODH_NOTEBOOK_NAMESPACE:-"rhods-notebooks"}
ODH_OPERATOR_PROJECT=${OPERATOR_NAMESPACE:-"redhat-ods-operator"}
## define label variables
NAMESPACE_LABEL="opendatahub.io/generated-namespace=true"
POD_SECURITY_LABEL="pod-security.kubernetes.io/enforce=baseline"
MONITOR_LABEL="openshift.io/cluster-monitoring=true"
## folder path
POD_SEC_DIR="pod-security-rbac"
PROMETHEUS_DIR="monitoring/prometheus"
## other variables
OC_CONSOLE_PROJECT="openshift-console"
RHODS_SELF_MANAGED=0

## create all oc project/namespace
# if user try to use their customized namespace this need to be done
for target_project in $ODH_PROJECT $ODH_NOTEBOOK_PROJECT $ODH_MONITORING_PROJECT $ODH_OPERATOR_PROJECT; do
  oc new-project "$target_project" 2>/dev/null || echo "INFO: $target_project project already exists."
done

## apply label to namespace $ODH_PROJECT
for LABEL in $NAMESPACE_LABEL $POD_SECURITY_LABEL; do
  oc label namespace "$ODH_PROJECT" "$LABEL" --overwrite=true || echo "INFO: $LABEL label already exists."
done

## apply label to namespace $ODH_NOTEBOOK_PROJECT
for LABEL in $NAMESPACE_LABEL; do
  oc label namespace "$ODH_NOTEBOOK_PROJECT" "$LABEL" --overwrite=true || echo "INFO: $LABEL label already exists."
done

## apply label to namespace $ODH_MONITORING_PROJECT
for LABEL in $NAMESPACE_LABEL $POD_SECURITY_LABEL $MONITOR_LABEL; do
  oc label namespace "$ODH_MONITORING_PROJECT" "$LABEL" --overwrite=true || echo "INFO: $LABEL label already exists."
done

# TODO: This part for 1.27->1.28 upgrade so it needs to be removed in 1.29
# ClusterRoleBiding name for modelmesh is changed so old CRB need to be removed for proper upgrade (RHODS-9245)
export old_odh_model_controller_crb_exit=true
oc get clusterrolebinding odh-model-controller-rolebinding-redhat-ods-applications > /dev/null 2>&1|| old_odh_model_controller_crb_exit=false
if [[ ${old_odh_model_controller_crb_exit} != "false" ]];then
  if [[ $(oc get clusterrolebinding odh-model-controller-rolebinding-redhat-ods-applications -ojsonpath='{.roleRef.name}') == "manager-role" ]]; then
      echo "Old ClusterRoleBinding for modelmesh is deleted"
      oc delete clusterrolebinding odh-model-controller-rolebinding-redhat-ods-applications
      oc create clusterrolebinding odh-model-controller-rolebinding-redhat-ods-applications --clusterrole=odh-model-controller-role --serviceaccount=redhat-ods-applications:odh-model-controller
  else
      echo "New ClusterRoleBinding for modelmesh is already upated."
  fi
fi
####################################################################################################
# RHODS ROLEBINDING
####################################################################################################

# Create Rolebinding for baseline permissions
oc apply -n "$ODH_PROJECT" -f $POD_SEC_DIR/applications-ns-rolebinding.yaml
oc apply -n "$ODH_MONITORING_PROJECT" -f $POD_SEC_DIR/monitoring-ns-rolebinding.yaml

# Set RHODS_SELF_MANAGED to 1, if addon-managed-odh-catalog not found.
oc get catalogsource -n "$ODH_OPERATOR_PROJECT" addon-managed-odh-catalog 2>/dev/null || RHODS_SELF_MANAGED=1
# echo "DEBUG: RHODS_SELF_MANAGED is set to $RHODS_SELF_MANAGED"

####################################################################################################
# KfDef
####################################################################################################

# in $ODH_PROJECT namespace
kfdef_yamls=(
  "rhods-anaconda.yaml"     # anaconda,
  "rhods-dashboard.yaml"    # Dashboard,
  "rhods-nbc.yaml"          # Notebook Controller,
  "rhods-model-mesh.yaml"   # Model Mesh,
  "rhods-data-science-pipelines-operator.yaml" # DSPO,
)
for kfdef_yaml in "${kfdef_yamls[@]}"
do
  oc apply -n "$ODH_PROJECT" -f "kfdefs/$kfdef_yaml"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Attempt to create CR failed by file $kfdef_yaml ."
  exit 1
  fi
done

# in $ODH_MONITORING_PROJECT namespace
kfdef_monitor_yamls=(
  "rhods-monitoring.yaml"  # Monitoring stack,
  "rhods-modelmesh-monitoring.yaml" # Model Mesh monitoring stack,
)
for kfdef_monitor_yaml in "${kfdef_monitor_yamls[@]}"
do
  oc apply -n "$ODH_MONITORING_PROJECT" -f "kfdefs/$kfdef_monitor_yaml"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Attempt to create CR failed by file $kfdef_monitor_yaml ."
  exit 1
  fi
done

# in $ODH_NOTEBOOK_PROJECT namespace
kfdef_nb_yamls=(
  "rhods-notebooks.yaml"   # Notebooks ImageStreams,
)
for kfdef_nb_yaml in "${kfdef_nb_yamls[@]}"
do
  oc apply -n "$ODH_NOTEBOOK_PROJECT" -f "kfdefs/$kfdef_nb_yamls"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Attempt to create CR failed by file $kfdef_nb_yamls ."
  exit 1
  fi
done

####################################################################################################
# PARTNERS ACCESS
####################################################################################################

# Modify anaconda secret if needed
kind="secret"
resource="anaconda-ce-access"
check=$(oc::object::safe::to::apply $kind $resource)
if [[ "$check" == "0" ]]; then
  oc apply -n "$ODH_PROJECT" -f partners/anaconda/anaconda-ce-access.yaml
elif  [ "$check" == "1" ];then
  echo "The Anaconda base secret \($kind/$resource\) has been modified. Skipping apply."
fi

####################################################################################################
# RHODS MONITORING
####################################################################################################

# Apply specific configuration for OSD environments
if [[ "$RHODS_SELF_MANAGED" -eq 0 ]]; then
  echo "INFO: Applying specific configuration for OSD environments."
  # Give dedicated-admins group CRUD access to ConfigMaps, Secrets, ImageStreams, Builds and BuildConfigs in select namespaces
  for target_project in $ODH_PROJECT $ODH_NOTEBOOK_PROJECT; do
    oc apply -n "$target_project" -f rhods-osd-configs.yaml
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Attempt to create the RBAC policy for dedicated admins group in $target_project failed."
      exit 1
      ## todo: kubectl get pod PD1 -n NS1 &> /dev/null && echo "true" || echo "false"
    fi
  done

  ####################################################################################################
  #  Prometheus
  ####################################################################################################

  # for monitoring/prometheus/prometheus-configs.yaml
  # Configure Dead Man's Snitch alerting
  deadmanssnitch=$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-deadmanssnitch -o jsonpath='{.data.SNITCH_URL}'" 4 90 | tr -d "'"  | base64 --decode)
  if [[ -z "$deadmanssnitch" ]]; then
      echo "ERROR: Dead Man Snitch secret does not exist."
      exit 1
  fi
  sed -i "s#<snitch_url>#\"$deadmanssnitch\"#g" $PROMETHEUS_DIR/prometheus-configs.yaml

  # Configure PagerDuty alerting
  redhat_rhods_pagerduty=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT" 5 60 )
  if [[ -z "$redhat_rhods_pagerduty" ]]; then
      echo "ERROR: Pagerduty secret does not exist."
      exit 1
  fi
  pagerduty_service_token=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT -o jsonpath='{.data.PAGERDUTY_KEY}'" 5 10)
  pagerduty_service_token=$(echo -ne "$pagerduty_service_token" | tr -d "'" | base64 --decode)
  sed -i "s/<pagerduty_token>/$pagerduty_service_token/g" $PROMETHEUS_DIR/prometheus-configs.yaml

  # Configure SMTP alerting
  redhat_rhods_smtp=$(oc::wait::object::availability "oc get secret redhat-rhods-smtp -n $ODH_MONITORING_PROJECT" 5 60 )
  if [[ -z "$redhat_rhods_smtp" ]]; then
      echo "ERROR: SMTP secret does not exist."
      exit 1
  fi
  sed -i "s/<smtp_host>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.host}'" 2 30 | tr -d "'"  | base64 --decode)/g" $PROMETHEUS_DIR/prometheus-configs.yaml
  sed -i "s/<smtp_port>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.port}'" 2 30 | tr -d "'"  | base64 --decode)/g" $PROMETHEUS_DIR/prometheus-configs.yaml
  sed -i "s/<smtp_username>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.username}'" 2 30 | tr -d "'"  | base64 --decode)/g" $PROMETHEUS_DIR/prometheus-configs.yaml
  sed -i "s/<smtp_password>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.password}'" 2 30 | tr -d "'"  | base64 --decode)/g" $PROMETHEUS_DIR/prometheus-configs.yaml

  # Configure the SMTP destination email
  addon_managed_odh_parameter=$(oc::wait::object::availability "oc get secret addon-managed-odh-parameters -n $ODH_OPERATOR_PROJECT" 5 60 )
  if [[ -z "$addon_managed_odh_parameter" ]];then
      echo "ERROR: Addon managed odh parameter secret does not exist."
      exit 1
  fi
  sed -i "s/<user_emails>/$(oc::wait::object::availability "oc get secret -n $ODH_OPERATOR_PROJECT addon-managed-odh-parameters -o jsonpath='{.data.notification-email}'" 2 30 | tr -d "'"  | base64 --decode)/g" $PROMETHEUS_DIR/prometheus-configs.yaml

  # Configure the SMTP sender email
  if [[ "$(oc get route -n $OC_CONSOLE_PROJECT console --template={{.spec.host}})" =~ "devshift.org" ]]; then
    sed -i "s/redhat-openshift-alert@devshift.net/redhat-openshift-alert@rhmw.io/g" $PROMETHEUS_DIR/prometheus-configs.yaml
  fi

  # Config alerts to SRE
  if [[ "$(oc get route -n $OC_CONSOLE_PROJECT console --template={{.spec.host}})" =~ "aisrhods" ]]; then
    echo "Cluster is for RHODS engineering or test purposes. Disabling SRE alerting."
    sed -i "s/receiver: PagerDuty/receiver: alerts-sink/g" $PROMETHEUS_DIR/prometheus-configs.yaml
  else
    echo "Cluster is not for RHODS engineering or test purposes."
  fi

  # for monitoring/prometheus/prometheus-secrets.yaml
  ## generate random value to apply prometheus secrets
  sed -i "s/<alertmanager_proxy_secret>/$(openssl rand -hex 32)/g" $PROMETHEUS_DIR/prometheus-secrets.yaml
  sed -i "s/<prometheus_proxy_secret>/$(openssl rand -hex 32)/g" $PROMETHEUS_DIR/prometheus-secrets.yaml
  oc create -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/prometheus-secrets.yaml || echo "INFO: Prometheus session secrets already exist."

  # for monitoring/prometheus/prometheus-configs.yaml
  ## set rhods dashboard host
  oc apply -n "$ODH_PROJECT" -f monitoring/rhods-dashboard-route.yaml
  rhods_dashboard_host=$(oc::wait::object::availability "oc get route rhods-dashboard -n $ODH_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
  sed -i "s/<rhods_dashboard_host>/$rhods_dashboard_host/g" $PROMETHEUS_DIR/prometheus-configs.yaml

  ## set nbc spawner host
  notebook_spawner_host="notebook-controller-service.$ODH_PROJECT.svc:8080\/metrics, odh-notebook-controller-service.$ODH_PROJECT.svc:8080\/metrics"
  sed -i "s/<notebook_spawner_host>/$notebook_spawner_host/g" $PROMETHEUS_DIR/prometheus-configs.yaml

  ## set dspo host
  data_science_pipelines_operator_host="data-science-pipelines-operator-service.$ODH_PROJECT.svc:8080\/metrics"
  sed -i "s/<data_science_pipelines_operator_host>/$data_science_pipelines_operator_host/g" $PROMETHEUS_DIR/prometheus-configs.yaml

  oc apply -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/prometheus-configs.yaml

  # for monitoring/prometheus/alertmanager-svc.yaml
  ## set alertmanager_host
  oc apply -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/alertmanager-svc.yaml
  alertmanager_host=$(oc::wait::object::availability "oc get route alertmanager -n $ODH_MONITORING_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
  sed -i "s/<set_alertmanager_host>/$alertmanager_host/g" $PROMETHEUS_DIR/prometheus.yaml

  ## set alertmanager_config_hash
  alertmanager_config_hash=$(oc get cm alertmanager -n "$ODH_MONITORING_PROJECT" -o jsonpath='{.data.alertmanager\.yml}' | openssl dgst -binary -sha256 | openssl base64)
  sed -i "s#<alertmanager_config_hash>#$alertmanager_config_hash#g" $PROMETHEUS_DIR/prometheus.yaml

  prometheus_config_hash=$(oc get cm prometheus -n "$ODH_MONITORING_PROJECT" -o jsonpath='{.data}' | openssl dgst -binary -sha256 | openssl base64)
  sed -i "s#<prometheus_config_hash>#$prometheus_config_hash#g" $PROMETHEUS_DIR/prometheus.yaml

  oc apply -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/prometheus.yaml

  # for monitoring/prometheus/prometheus-viewer-rolebinding.yaml
  ## set odh_mointoring_project in ODH_PROJECT namespace
  oc apply -n "$ODH_PROJECT" -f $PROMETHEUS_DIR/prometheus-viewer-rolebinding.yaml

  # for $PROMETHEUS_DIR/blackbox-exporter-common.yaml
  ## configure Blackbox exporter in ODH_MONITORING_PROJECT namespace
  oc apply -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/blackbox-exporter-common.yaml

  # for blackbox-exporter-internal.yaml or blackbox-exporter-external.yaml
  if [[ "$(oc get route -n $OC_CONSOLE_PROJECT console --template={{.spec.host}})" =~ "redhat.com" ]]; then
    oc apply -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/blackbox-exporter-internal.yaml
  else
    oc apply -n "$ODH_MONITORING_PROJECT" -f $PROMETHEUS_DIR/blackbox-exporter-external.yaml
  fi

# Apply specific configuration for self-managed environments
else
    echo "INFO: Applying specific configuration for self-managed environments: None"
fi

####################################################################################################
# Configure Serving Runtime resources
####################################################################################################

echo "Creating Serving Runtime resources..."
oc apply -n ${ODH_PROJECT} -k odh-dashboard/modelserving

# Add segment.io secret key & configmap
oc apply -n "$ODH_PROJECT" -f monitoring/segment-key-secret.yaml
oc apply -n "$ODH_PROJECT" -f monitoring/segment-key-config.yaml

####################################################################################################
# RHODS DASHBOARD
####################################################################################################

# Add consoleLink CR to default namespace to provide URL to rhods-dashboard via the Application Launcher in OpenShift
# for odh-dashboard/consolelink/consolelink.yaml
cluster_domain=$(oc get ingresses.config.openshift.io cluster --template {{.spec.domain}})
odh_dashboard_url="https://rhods-dashboard-$ODH_PROJECT.$cluster_domain"
sed -i "s#<rhods-dashboard-url>#$odh_dashboard_url#g" odh-dashboard/consolelink/consolelink.yaml
oc apply -f odh-dashboard/consolelink/consolelink.yaml

# Apply ISVs for dashboard
# for odh-dashboard/crds/* (except odh-dashbaord-crd.yaml) odh-dashboard/apps-onprem/* odh-dashboard/apps-managed-service/*
oc::dashboard::apply::isvs "$ODH_PROJECT"

# TODO: can this be added into isvs function()?
# Deploying the ODHDashboardConfig CRD
# for odh-dashboard/odh-dashbaord-crd.yaml
oc apply -n "$ODH_PROJECT" -f odh-dashboard/crds/odh-dashboard-crd.yaml
odhdashboardconfigcrd=$(oc::wait::object::availability "oc get crd odhdashboardconfigs.opendatahub.io" 30 60)
if [[ -z "$odhdashboardconfigcrd" ]]; then
  echo "ERROR: OdhDashboardConfig CRD does not exist."
  exit 1
fi

# for dashboard configs/odh-enabled-applications-config.configmap.yaml
kind="configmap"
resource="odh-enabled-applications-config"
#TODO: This should probably exist in odh-manifests due to the fact that it controls enabled applications
check_enableconfig=$(oc::object::safe::to::apply "$kind" "$resource")
if [[ "$check_enableconfig" == "0" ]]; then
  oc apply -n "$ODH_PROJECT" -f odh-dashboard/configs/odh-enabled-applications-config.configmap.yaml
else
  echo "The ODH Dashboard enabled-applications-config ($kind/$resource) has been modified. Skipping apply."
fi

# for dashboard configs/odh-dashboard-config.yaml
if [[ "$RHODS_SELF_MANAGED" -eq 1 ]]; then
  ADMIN_GROUPS="rhods-admins"
  oc adm groups new "$ADMIN_GROUPS" || echo "rhods-admins group already exists"
else
  ADMIN_GROUPS="dedicated-admins"
fi
sed -i "s|<admin_groups>|$ADMIN_GROUPS|g" odh-dashboard/configs/odh-dashboard-config.yaml
# If this is a pre-existing cluster (ie: we are upgrading), then we will not touch the ODHDashboardConfig resource
#TODO: This controls feature flags and notebook controller presets like Notebook size. 
# Confirm that notebook sizes can be configured external to the ODHDashboardConfig CR
kind="odhdashboardconfigs"
resource="odh-dashboard-config"
check_dashboardconfig=$(oc::object::safe::to::apply "$kind" "$resource")
if [[ "$check_dashboardconfig" == "0" ]]; then
  oc apply -n "$ODH_PROJECT" -f odh-dashboard/configs/odh-dashboard-config.yaml
elif [[ "$check_dashboardconfig" == "1" ]]; then
  echo "The ODHDashboardConfig ($kind/$resource) has been modified. Skipping apply"
else
  echo "The ODHDashboardConfig ($kind/$resource) already exists"
fi

####################################################################################################
# RHODS NETPOL
####################################################################################################
# Add network policies
# for network/*
oc apply -n "$ODH_PROJECT" -f network/applications_network_policy.yaml
oc apply -n "$ODH_MONITORING_PROJECT" -f network/monitoring_network_policy.yaml
oc apply -n "$ODH_OPERATOR_PROJECT" -f network/operator_network_policy.yaml
