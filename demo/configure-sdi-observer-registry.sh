#!/bin/bash
 
  ## Change Namespace to sdi-observer
  NAMESPACE="${NAMESPACE:-sdi-observer}"
  oc project sdi-observer
 
  ## Obtain registry credentials
  reg_credentials=$(oc get -n "${NAMESPACE:-sdi-observer}" secret/container-image-registry-htpasswd -o jsonpath='{.data.\.htpasswd\.raw }'  | base64 -d )
  reg_user=$(echo $reg_credentials| cut -d: -f1)
  reg_pw=$(echo $reg_credentials| cut -d: -f2)
 
  ## Obtain registry hostname
  reg_hostname="$(oc get route -n "${NAMESPACE:-sdi-observer}" container-image-registry -o jsonpath='{.spec.host}')"
  echo "=================================================" | tee registry-credentials.txt
  echo "Using registry: $reg_hostname"                     | tee -a registry-credentials.txt
  echo "USER: $reg_user"                                   | tee -a registry-credentials.txt
  echo "PW  : $reg_pw"                                     | tee -a registry-credentials.txt
  echo "=================================================" | tee -a registry-credentials.txt
 
  if [ -z "$reg_user" -o -z "$reg_pw" ]; then
             echo "Something went wrong. Check if the pods are running"
             exit 1
  fi
 
  #set -x
  ### Obtain Ingress Router's default self-signed CA certificate
  mkdir -p "/etc/containers/certs.d/${reg_hostname}"
  router_ca_crt="/etc/containers/certs.d/${reg_hostname}/router-ca.crt"
  oc get secret -n openshift-ingress-operator -o json router-ca | \
      jq -r '.data as $d | $d | keys[] | select(test("\\.crt$")) | $d[.] ' | base64 -d > ${router_ca_crt}
 
  ### test via curl
  curl -k -I --user ${reg_credentials}  --cacert ${router_ca_crt} "https://${reg_hostname}/v2/"
 
  ### test via podman
  echo $reg_pw |  podman login -u $reg_user --password-stdin ${reg_hostname}
 
  reg_login_ok=$?
 
  if [ $reg_login_ok ]; then
    # Configure Openshift to trust container registry (8.2)
    echo "Configure Openshift to trust container registry"
    echo "CTRL-C to stop, ENTER to continue"
    read zz
    caBundle="$(oc get -n openshift-ingress-operator -o json secret/router-ca | \
      jq -r '.data as $d | $d | keys[] | select(test("\\.(?:crt|pem)$")) | $d[.]' | base64 -d)"
    # determine the name of the CA configmap if it exists already
    cmName="$(oc get images.config.openshift.io/cluster -o json | \
      jq -r '.spec.additionalTrustedCA.name // "trusted-registry-cabundles"')"
    if oc get -n openshift-config "cm/$cmName" 2>/dev/null; then
      # configmap already exists -> just update it
      oc get -o json -n openshift-config "cm/$cmName" | \
          jq '.data["'"${reg_hostname//:/..}"'"] |= "'"$caBundle"'"' | \
          oc replace -f - --force
    else
        # creating the configmap for the first time
        oc create configmap -n openshift-config "$cmName" \
            --from-literal="${reg_hostname//:/..}=$caBundle"
        oc patch images.config.openshift.io cluster --type=merge \
            -p '{"spec":{"additionalTrustedCA":{"name":"'"$cmName"'"}}}'
    fi
    # Check that the certifcate is deployed
    sleep 20 # wait for distribution of certificates
    echo "======== Configured Registries =========="
    oc rsh -n openshift-image-registry "$(oc get pods -n openshift-image-registry -l docker-registry=default | \
          awk '/Running/ {print $1; exit}')" ls -1 /etc/pki/ca-trust/source/anchors
     
  else
    echo "Registry setup failed, please repair before you continue"
  fi

