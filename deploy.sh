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

function oc::dashboard::apply::isvs() {
  local crd_arr=(
    "odhapplications.dashboard.opendatahub.io"
    "odhdocuments.dashboard.opendatahub.io"
    "odhquickstarts.console.openshift.io"
  )

  oc apply -n ${ODH_PROJECT} -k odh-dashboard/crds
  for crd_name in ${crd_arr[@]}
  do
    dashboard_crd=$(oc::wait::object::availability "oc get crd $crd_name" 30 60)
    if [ -z "$dashboard_crd" ];then
      echo "ERROR: $crd_name CRD does not exist."
      exit 1
    fi
  done

  oc apply -n ${ODH_PROJECT} -k odh-dashboard/apps-on-prem
  if [ $? -ne 0 ]; then
    echo "ERROR: Attempt to install the default Dashboard ISVs application tiles failed"
    exit 1
  fi

  # Embedding the command in the IF statement since bash SHELLOPT "errexit" is enabled
  #    and the script will exit immediately when this command fails
  if [ "$RHODS_SELF_MANAGED" -eq 0 ]; then
    # Managed services has both the on prem and managed service additons.
    oc apply -n ${ODH_PROJECT} -k odh-dashboard/apps-managed-service

    if [ $? -ne 0 ]; then
      echo "ERROR: Attempt to install the Dashaboard ISVs application tiles for managed services failed"
      exit 1
    fi
  fi
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

function add_servingruntime_config() {
  # Get OpenVino image from latest CSV
  openvino_img=$(oc get csv -l operators.coreos.com/rhods-operator.redhat-ods-operator -n $ODH_OPERATOR_PROJECT -o=jsonpath='{.items[-1].spec.install.spec.deployments[?(@.name == "rhods-operator")].spec.template.spec.containers[?(@.name == "rhods-operator")].env[?(@.name == "RELATED_IMAGE_ODH_OPENVINO_IMAGE")].value}')
    
  # Replace image
  sed -i "s|<openvino_image>|${openvino_img}|g" model-mesh/serving_runtime_config.yaml

  # Check if the configmap exists
  configmap_exists=$(oc get -n $ODH_PROJECT configmap/servingruntimes-config -o name | grep configmap/servingruntimes-config || echo "false")

  # Check if the key default-config exists
  default_config_key_exists=$(oc get -n $ODH_PROJECT configmap/servingruntimes-config -o jsonpath='{.data}' | grep "default-config" || echo "false")

  if [ "$configmap_exists" == "false" ]; then
    echo "ConfigMap servingruntimes-config doesn't exist, creating it with the default configuration"
    oc apply -f model-mesh/serving_runtime_config.yaml -n $ODH_PROJECT
    return 0
  elif [ "$default_config_key_exists" == "false" ]; then
    echo "Key default-config doesn't exist in ConfigMap servingruntimes-config applying the key"
    oc patch -n $ODH_PROJECT configmap/servingruntimes-config --patch-file model-mesh/serving_runtime_config.yaml
    return 0
  else
    echo "Key default-config exists in ConfigMap servingruntimes-config, reverting the configuration to the initial state and updating openvino image"
    oc patch -n $ODH_PROJECT configmap/servingruntimes-config --patch-file model-mesh/serving_runtime_config.yaml
    return 0
  fi
  return 1
}

ODH_PROJECT=${ODH_CR_NAMESPACE:-"redhat-ods-applications"}
ODH_MONITORING_PROJECT=${ODH_MONITORING_NAMESPACE:-"redhat-ods-monitoring"}
ODH_NOTEBOOK_PROJECT=${ODH_NOTEBOOK_NAMESPACE:-"rhods-notebooks"}
ODH_OPERATOR_PROJECT=${OPERATOR_NAMESPACE:-"redhat-ods-operator"}
NAMESPACE_LABEL="opendatahub.io/generated-namespace=true"
POD_SECURITY_LABEL="pod-security.kubernetes.io/enforce=baseline"

oc new-project ${ODH_PROJECT} || echo "INFO: ${ODH_PROJECT} project already exists."
oc label namespace $ODH_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."
oc label namespace $ODH_PROJECT  $POD_SECURITY_LABEL --overwrite=true || echo "INFO: ${POD_SECURITY_LABEL} label already exists."

oc new-project ${ODH_NOTEBOOK_PROJECT} || echo "INFO: ${ODH_NOTEBOOK_PROJECT} project already exists."
oc label namespace $ODH_NOTEBOOK_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."

oc new-project $ODH_MONITORING_PROJECT || echo "INFO: $ODH_MONITORING_PROJECT project already exists."
oc label namespace $ODH_MONITORING_PROJECT openshift.io/cluster-monitoring=true --overwrite=true
oc label namespace $ODH_MONITORING_PROJECT  $NAMESPACE_LABEL --overwrite=true || echo "INFO: ${NAMESPACE_LABEL} label already exists."
oc label namespace $ODH_MONITORING_PROJECT  $POD_SECURITY_LABEL --overwrite=true || echo "INFO: ${POD_SECURITY_LABEL} label already exists."

# Create Rolebinding for baseline permissions
oc apply -n ${ODH_PROJECT} -f pod-security-rbac/applications-ns-rolebinding.yaml
oc apply -n ${ODH_MONITORING_PROJECT} -f pod-security-rbac/monitoring-ns-rolebinding.yaml
# If rhodsquickstart CRD is found, delete it. Note: Remove this code in 1.19
oc delete crd rhodsquickstarts.console.openshift.io 2>/dev/null || echo "INFO: Unable to delete Rhodsquickstart CRD"

# Set RHODS_SELF_MANAGED to 1, if addon installation not found.
RHODS_SELF_MANAGED=0
oc get catalogsource -n ${ODH_OPERATOR_PROJECT} addon-managed-odh-catalog || RHODS_SELF_MANAGED=1

# TODO: Remove in 1.21
# If buildconfigs with label rhods/buildchain=cuda-* found, delete them (replaced by pre-build notebooks).
oc delete buildconfig -n redhat-ods-applications -l rhods/buildchain

# TODO: Remove in 1.21
# If imagestreams with label rhods/buildchain=cuda-* found, delete them (replaced by pre-build notebooks).
oc delete imagestreams -n redhat-ods-applications -l rhods/buildchain

# Apply isvs for dashboard
oc::dashboard::apply::isvs

# Create KfDef for RHODS Dashboard
oc apply -n ${ODH_PROJECT} -f rhods-dashboard.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the Dashboard CR failed."
  exit 1
fi

# Create KfDef for RHODS Notebook Controller
oc apply -n ${ODH_PROJECT} -f rhods-nbc.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the Notebook Controller CR failed."
  exit 1
fi

oc apply -n ${ODH_PROJECT} -f rhods-model-mesh.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the Model Mesh CR failed."
  exit 1
fi

# Create Kfdef for RHODS Data Science pipelines operator
oc apply -n ${ODH_PROJECT} -f rhods-data-science-pipelines-operator.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the Data Science Pipelines Operator CR failed."
  exit 1
fi

# Create KfDef for RHODS Notebooks ImageStreams
oc apply -n ${ODH_NOTEBOOK_PROJECT} -f rhods-notebooks.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the RHODS Notebooks CR failed."
  exit 1
fi

# Create KfDef for RHODS monitoring stack
oc apply -n ${ODH_MONITORING_PROJECT} -f rhods-monitoring.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the RHODS monitoring stack failed."
  exit 1
fi

# Create KfDef for RHODS Model Mesh monitoring stack
oc apply -n ${ODH_MONITORING_PROJECT} -f rhods-modelmesh-monitoring.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the RHODS monitoring stack failed."
  exit 1
fi

# Create KfDef for Anaconda
oc apply -n ${ODH_PROJECT} -f rhods-anaconda.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the anaconda CR failed."
  exit 1
fi

if oc::object::safe::to::apply secret anaconda-ce-access; then
  oc apply -n ${ODH_PROJECT} -f partners/anaconda/anaconda-ce-access.yaml
else
  echo "The Anaconda base secret (secret/anaconda-ce-access) has been modified. Skipping apply."
fi

# Apply specific configuration for OSD environments
if [ "$RHODS_SELF_MANAGED" -eq 0 ]; then

  echo "INFO: Applying specific configuration for OSD environments."

  # Give dedicated-admins group CRUD access to ConfigMaps, Secrets, ImageStreams, Builds and BuildConfigs in select namespaces
  for target_project in ${ODH_PROJECT} ${ODH_NOTEBOOK_PROJECT}; do
    oc apply -n $target_project -f rhods-osd-configs.yaml
    if [ $? -ne 0 ]; then
      echo "ERROR: Attempt to create the RBAC policy for dedicated admins group in $target_project failed."
      exit 1
    fi
  done

  # Configure Dead Man's Snitch alerting
  deadmanssnitch=$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-deadmanssnitch -o jsonpath='{.data.SNITCH_URL}'" 4 90 | tr -d "'"  | base64 --decode)
  if [ -z "$deadmanssnitch" ];then
      echo "ERROR: Dead Man Snitch secret does not exist."
      exit 1
  fi
  sed -i "s#<snitch_url>#$deadmanssnitch#g" monitoring/prometheus/prometheus-configs.yaml

  # Configure PagerDuty alerting
  redhat_rhods_pagerduty=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT" 5 60 )
  if [ -z "$redhat_rhods_pagerduty" ];then
      echo "ERROR: Pagerduty secret does not exist."
      exit 1
  fi
  pagerduty_service_token=$(oc::wait::object::availability "oc get secret redhat-rhods-pagerduty -n $ODH_MONITORING_PROJECT -o jsonpath='{.data.PAGERDUTY_KEY}'" 5 10)
  pagerduty_service_token=$(echo -ne "$pagerduty_service_token" | tr -d "'" | base64 --decode)
  sed -i "s/<pagerduty_token>/$pagerduty_service_token/g" monitoring/prometheus/prometheus-configs.yaml

  # Configure SMTP alerting
  redhat_rhods_smtp=$(oc::wait::object::availability "oc get secret redhat-rhods-smtp -n $ODH_MONITORING_PROJECT" 5 60 )
  if [ -z "$redhat_rhods_smtp" ];then
      echo "ERROR: SMTP secret does not exist."
      exit 1
  fi
  sed -i "s/<smtp_host>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.host}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
  sed -i "s/<smtp_port>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.port}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
  sed -i "s/<smtp_username>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.username}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml
  sed -i "s/<smtp_password>/$(oc::wait::object::availability "oc get secret -n $ODH_MONITORING_PROJECT redhat-rhods-smtp -o jsonpath='{.data.password}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml

  # Configure the SMTP destination email
  addon_managed_odh_parameter=$(oc::wait::object::availability "oc get secret addon-managed-odh-parameters -n $ODH_OPERATOR_PROJECT" 5 60 )
  if [ -z "$addon_managed_odh_parameter" ];then
      echo "ERROR: Addon managed odh parameter secret does not exist."
      exit 1
  fi
  sed -i "s/<user_emails>/$(oc::wait::object::availability "oc get secret -n $ODH_OPERATOR_PROJECT addon-managed-odh-parameters -o jsonpath='{.data.notification-email}'" 2 30 | tr -d "'"  | base64 --decode)/g" monitoring/prometheus/prometheus-configs.yaml

  # Configure the SMTP sender email
  if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"devshift.org".* ]]; then
    sed -i "s/redhat-openshift-alert@devshift.net/redhat-openshift-alert@rhmw.io/g" monitoring/prometheus/prometheus-configs.yaml
  fi

  if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"aisrhods".* ]]; then
    echo "Cluster is for RHODS engineering or test purposes. Disabling SRE alerting."
    sed -i "s/receiver: PagerDuty/receiver: alerts-sink/g" monitoring/prometheus/prometheus-configs.yaml
  else
    echo "Cluster is not for RHODS engineering or test purposes."
  fi

  # Configure Prometheus
  oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/alertmanager-svc.yaml
  alertmanager_host=$(oc::wait::object::availability "oc get route alertmanager -n $ODH_MONITORING_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
  sed -i "s/<set_alertmanager_host>/$alertmanager_host/g" monitoring/prometheus/prometheus.yaml

  sed -i "s/<alertmanager_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/prometheus/prometheus-secrets.yaml

  sed -i "s/<prometheus_proxy_secret>/$(openssl rand -hex 32)/g" monitoring/prometheus/prometheus-secrets.yaml
  oc create -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus-secrets.yaml || echo "INFO: Prometheus session secrets already exist."

  oc apply -f monitoring/rhods-dashboard-route.yaml -n $ODH_PROJECT
  rhods_dashboard_host=$(oc::wait::object::availability "oc get route rhods-dashboard -n $ODH_PROJECT -o jsonpath='{.spec.host}'" 2 30 | tr -d "'")
  sed -i "s/<rhods_dashboard_host>/$rhods_dashboard_host/g" monitoring/prometheus/prometheus-configs.yaml

  notebook_spawner_host="notebook-controller-service.$ODH_PROJECT.svc:8080\/metrics,odh-notebook-controller-service.$ODH_PROJECT.svc:8080\/metrics"
  sed -i "s/<notebook_spawner_host>/$notebook_spawner_host/g" monitoring/prometheus/prometheus-configs.yaml

  oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus-configs.yaml

  alertmanager_config=$(oc get cm alertmanager -n $ODH_MONITORING_PROJECT -o jsonpath='{.data.alertmanager\.yml}' | openssl dgst -binary -sha256 | openssl base64)
  sed -i "s#<alertmanager_config_hash>#$alertmanager_config#g" monitoring/prometheus/prometheus.yaml

  prometheus_config=$(oc get cm prometheus -n $ODH_MONITORING_PROJECT -o jsonpath='{.data}' | openssl dgst -binary -sha256 | openssl base64)
  sed -i "s#<prometheus_config_hash>#$prometheus_config#g" monitoring/prometheus/prometheus.yaml
  oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/prometheus.yaml

  sed -i "s#<odh_monitoring_project>#$ODH_MONITORING_PROJECT#g" monitoring/prometheus/prometheus-viewer-rolebinding.yaml
  oc apply -n $ODH_PROJECT -f monitoring/prometheus/prometheus-viewer-rolebinding.yaml

  # Configure Blackbox exporter
  oc apply -n $ODH_MONITORING_PROJECT -f monitoring/prometheus/blackbox-exporter-common.yaml

  if [[ "$(oc get route -n openshift-console console --template={{.spec.host}})" =~ .*"redhat.com".* ]]; then
    oc apply -f monitoring/prometheus/blackbox-exporter-internal.yaml -n $ODH_MONITORING_PROJECT
  else
    oc apply -f monitoring/prometheus/blackbox-exporter-external.yaml -n $ODH_MONITORING_PROJECT
  fi

# Apply specific configuration for self-managed environments
else
    echo "INFO: Applying specific configuration for self-managed environments."
fi

# Configure Serving Runtime resources
echo "Creating Serving Runtime resources..."
add_servingruntime_config

# Add segment.io secret key & configmap
oc apply -n ${ODH_PROJECT} -f monitoring/segment-key-secret.yaml
oc apply -n ${ODH_PROJECT} -f monitoring/segment-key-config.yaml

# Add consoleLink CR to provide a link to the rhods-dashboard via the Application Launcher in OpenShift
cluster_domain=$(oc get ingresses.config.openshift.io cluster --template {{.spec.domain}})
odh_dashboard_route="https://rhods-dashboard-$ODH_PROJECT.$cluster_domain"
sed -i "s#<rhods-dashboard-url>#$odh_dashboard_route#g" consolelink/consolelink.yaml
oc apply -f consolelink/consolelink.yaml

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
ADMIN_GROUPS="dedicated-admins"

if [ "$RHODS_SELF_MANAGED" -eq 1 ]; then
  ADMIN_GROUPS="rhods-admins"
  oc adm groups new ${ADMIN_GROUPS} || echo "rhods-admins group already exists"
fi
sed -i "s|<admin_groups>|$ADMIN_GROUPS|g" odh-dashboard/configs/odh-dashboard-config.yaml

exists=$(oc get -n $ODH_PROJECT ${kind} ${object} -o name | grep ${object} || echo "false")
# If this is a pre-existing cluster (ie: we are upgrading), then we will not touch the ODHDashboardConfig resource
#TODO: This controls feature flags and notebook controller presets like Notebook size. Confirm that notebook sizes can be configured external to the ODHDashboardConfig CR
if [ "$exists" == "false" ]; then
  if oc::object::safe::to::apply ${kind} ${resource}; then
    oc apply -n ${ODH_PROJECT} -f odh-dashboard/configs/odh-dashboard-config.yaml
  else
    echo "The ODHDashboardConfig (${kind}/${resource}) has been modified. Skipping apply."
  fi
else
   echo "The ODHDashboardConfig (${kind}/${resource}) already exists"
fi

####################################################################################################
# END RHODS DASHBOARD
####################################################################################################

# Add network policies
oc apply -f network/
