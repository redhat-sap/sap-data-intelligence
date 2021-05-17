#!/bin/bash

# change to the SDI_NAMESPACE
oc project "${SDI_NAMESPACE:-sdi}"
oc adm policy add-scc-to-group anyuid "system:serviceaccounts:$(oc project -q)"
oc adm policy add-scc-to-user privileged -z "$(oc project -q)-elasticsearch"
oc adm policy add-scc-to-user privileged -z "$(oc project -q)-fluentd"
oc adm policy add-scc-to-user privileged -z default
oc adm policy add-scc-to-user privileged -z mlf-deployment-api
oc adm policy add-scc-to-user privileged -z vora-vflow-server
oc adm policy add-scc-to-user privileged -z "vora-vsystem-$(oc project -q)"
oc adm policy add-scc-to-user privileged -z "vora-vsystem-$(oc project -q)-vrep"

