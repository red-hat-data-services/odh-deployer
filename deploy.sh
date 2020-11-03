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

# this is the value hardcoded in the CR yaml
CR_NAMESPACE_VALUE=opendatahub

ODH_PROJECT=${ODH_CR_NAMESPACE:-${CR_NAMESPACE_VALUE}}

# add a namespace flag for the apply command if necessary
NAMESPACE_FLAG=
if [ ${ODH_PROJECT} != ${CR_NAMESPACE_VALUE} ]; then
    NAMESPACE_FLAG="--namespace=${CR_NAMESPACE_VALUE}"
fi

oc new-project ${ODH_PROJECT} || echo "${ODH_PROJECT} project already exists."

while true; do
  oc apply -n ${ODH_PROJECT} -f /opendatahub.yaml ${NAMESPACE_FLAG}
  if [ $? -ne 0 ]; then
    echo "Attempt to create the ODH CR failed.  This is expected during operator installation."
  fi
  sleep 30s
done
