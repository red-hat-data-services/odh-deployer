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

ODH_PROJECT=${ODH_CR_NAMESPACE:-"opendatahub"}

oc new-project ${ODH_PROJECT} || echo "INFO: ${ODH_PROJECT} project already exists."

oc apply -n ${ODH_PROJECT} -f /opendatahub.yaml
if [ $? -ne 0 ]; then
  echo "ERROR: Attempt to create the ODH CR failed."
  exit 1
fi

oc new-project redhat-monitoring || echo "INFO: redhat-monitoring project already exists."

oc apply -n redhat-monitoring -f /grafana.yaml
