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

#set -e -o pipefail

ODH_NOTEBOOK_PROJECT=${ODH_NOTEBOOK_NAMESPACE:-"rhods-notebooks"}

for pod in $(oc get pods -n "${ODH_NOTEBOOK_PROJECT}" | grep -E 'jupyterhub-nb' | awk '{print $1}')
do
  export new_pod_name=$(sed "${pod}/jupyterhub/jupyter/")
  cp kfnbc/notebook_template.yaml kfnbc/notebook_template_${pod}.yaml
  oc get pod "${pod}" -o yaml | yq '.spec' | sed 's/^/        /' >> kfnbc/notebook_template_${pod}.yaml
  sed -i "s/<notebook_pod_name>/$new_pod_name/g" kfnbc/notebook_template_${pod}.yaml
done
 # <notebook_pod_name>

 # Make sure to add stuff around pvcs, environment secrets and configs