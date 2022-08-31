If the source reference for pytorch or tensorflow changes
or the ultimate base image changes, you MUST increment the output
tags for pytorch and/or tensorflow.

(Otherwise the tag may match an older image and the new images will not be used on an
upgraded installation if the workers have the old image cached)

The intermediate images between the base image and pytorch and tensorflow will always be
re-pulled by the openshift builds, and so they can always use the default "latest" tag
without causing a problem.

The "-N" string at the end of the pytorch and tensorflow tags are an incrementing
value that you can use to produce a new tag.

For example (same applies to tensorflow):

- kind: BuildConfig
  apiVersion: build.openshift.io/v1
  metadata:
    name: s2i-pytorch-gpu-cuda-11.4.2-notebook
    labels:
      opendatahub.io/build_type: "notebook_image"
      opendatahub.io/notebook-name: "PyTorch"
      rhods/buildchain: cuda
  spec:
    nodeSelector: null
    output:
      to:
        kind: ImageStreamTag
        name: 'pytorch:py3.8-cuda-11.4.2-1'   <<<<<<<<< This must be changed to pytorch:py3.8-cuda-11.4.2-2 ..... (read on) ...
    resources:
      limits:
        cpu: "4"
        memory: 8Gi
      requests:
        cpu: "4"
        memory: 8Gi
    completionDeadlineSeconds: 1800
    successfulBuildsHistoryLimit: 1
    failedBuildsHistoryLimit: 1
    strategy:
      type: Source
      sourceStrategy:
        from:
          kind: ImageStreamTag
          name: 'minimal-gpu:py3.8-cuda-11.4.2'
    postCommit: {}
    source:
      type: Git
      git:
        uri: 'https://github.com/red-hat-data-services/s2i-pytorch-notebook'
        ref: nb-4                                                                <<<<<<<<<<< ... if this tag changes or the ultimate base image changes
    triggers:
      - type: ImageChange
        imageChange: {}
    runPolicy: SerialLatestOnly
