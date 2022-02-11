#!/bin/bash

ODH_PROJECT=${ODH_CR_NAMESPACE:-"redhat-ods-applications"}
checksum=false
version=false

function delete_tags() {
    local name=$1
    local tags=

    tags=$(oc get imagestream $name -n $ODH_PROJECT -o jsonpath={.status.tags[*].tag})
    if [ "$?" -eq 0 ]; then
	for t in ${tags[*]}; do
	    oc tag -d $ODH_PROJECT/$name:$t
	done
    fi
}

function delete_tags_for_prebuilts() {
    local is=

    is=($(oc get imagestream -l rhods/prebuilt -n $ODH_PROJECT -o jsonpath=' {range .items [*]} {.metadata.name}'))
    for name in ${is[*]}; do
	delete_tags $name
    done
}

# Figure out if the RHODS version has changed or the buildchain manifest checksum
res=$(oc get cm rhods-buildchain -n $ODH_PROJECT)
if [ "$?" -eq 0 ]; then
    # See if the version matches
    vers=$(oc get cm rhods-buildchain -n $ODH_PROJECT -o jsonpath='{.data.rhods-version}')
    if [ "$vers" != "$RHODS_VERSION" ]; then
        # The fact that the version is different doesn't necessarily mean
        # that the checksum is different ...
        version=true
        echo rhods-buildchain version does not match
        echo "    found: $vers"
        echo "    current: $RHODS_VERSION"
    else
        echo rhods-buildchain version matches
    fi
    cs=$(oc get cm rhods-buildchain -n $ODH_PROJECT -o jsonpath='{.data.manifest-checksum}')
    read line < $HOME/manifest-checksum
    if [ "$cs" != "$line" ]; then
        checksum=true
        echo rhods-buildchain checksum does not match
        echo "    found: $cs"
        echo "    current: $line"
    else
        echo rhods-buildchain checksum matches
    fi
else
    echo rhods-buildchain configmap missing
    version=true
    checksum=true
fi

if [ "$version" == "true" ]; then
    # For the prebuilt images, the operator is going to potentially add a new tag
    # Delete the existing tags and let the operator fill in the new ones
    delete_tags_for_prebuilts
fi

# Handle relabeling or recreating the buildchain objects
if [ "$checksum" == "true" ]; then
    echo recreating the runtime buildchain
    oc delete buildconfig -l rhods/buildchain -n $ODH_PROJECT
    oc delete is -l rhods/buildchain -n $ODH_PROJECT
    oc apply -f $HOME/jupyterhub/cuda-11.4.2/manifests.yaml -n $ODH_PROJECT

elif [ "$version" == "true" ]; then
    echo relabeling build objects with "$RHODS_VERSION"

    bc=($(oc get buildconfig -l rhods/buildchain -n $ODH_PROJECT -o jsonpath=' {range .items [*]} {.metadata.name}'))
    for name in ${bc[*]}; do
        oc label buildconfig -n $ODH_PROJECT "$name" rhods/buildchain=cuda-"$RHODS_VERSION" --overwrite=true
    done

    bu=($(oc get build -l rhods/buildchain -n $ODH_PROJECT -o jsonpath=' {range .items [*]} {.metadata.name}'))
    for name in ${bu[*]}; do
        oc label build -n $ODH_PROJECT "$name" rhods/buildchain=cuda-"$RHODS_VERSION" --overwrite=true
    done

    is=($(oc get imagestream -l rhods/buildchain -n $ODH_PROJECT -o jsonpath=' {range .items [*]} {.metadata.name}'))
    for name in ${is[*]}; do
        oc label imagestream -n $ODH_PROJECT "$name" rhods/buildchain=cuda-"$RHODS_VERSION" --overwrite=true
    done
fi

# We always do this, to make sure that checksum and version match
# whether we're creating it, modifying it, or making no net change
if [ "$checksum" == "true" -o "$version" == "true" ]; then
    echo updating rhods-buildchain configmap
    oc create --save-config cm rhods-buildchain \
       --from-file=$HOME/manifest-checksum \
       --from-literal=rhods-version="$RHODS_VERSION" \
       --dry-run=client -o yaml -n $ODH_PROJECT | oc apply -f -
fi
