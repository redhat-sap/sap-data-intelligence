local params = import 'common-parameters.libsonnet';
local base = import 'job-template.libsonnet';
local obsbc = import 'observer-buildconfig.libsonnet';
local obssa = import 'observer-serviceaccount.libsonnet';

base {
  local regjobtmpl = self,
  resourceName: 'deploy-registry',
  jobImage: null,
  command: regjobtmpl.resourceName + '.sh',
  createdBy:: 'registry-deploy',
  version:: error 'version must be specified',

  local bc = obsbc {
    createdBy:: regjobtmpl.createdBy,
    version:: regjobtmpl.version,
  },

  metadata+: {
    annotations+: {
      'openshift.io/display-name': |||
        Job to deploy a container image registry.
      |||,
      description: |||
        The template deploys a container image registry pod suitable to host SAP Data Intelligence
        images mirrored from SAP's registry. It is also supported for graph images built and
        scheduled by Data Intelligence's Pipeline Modeler. By default, the registry requires
        authentication. It is exposed by a OpenShift Ingress controller as an encrypted route. The
        route is secured by a certificate signed by the Ingress certificate authority. The
        registry can be accessed by SAP Software Lifecycle Bridge and Pipeline Modeler only via
        this route.

        It is recommended to choose as a storage class the one supporting RedWriteMany access mode
        if there is one. In such case, SDI_REGISTRY_VOLUME_ACCESS_MODE parameter shall be set to
        ReadWriteMany.

        Unless explicitly specified in template parameters, access credentials will be generated.
      |||,
    },
  },
  message: |||
    To get the credentials to access the registry, execute the following:

        # oc get -o go-template='{{index .data ".htpasswd.raw"}}' \
          secret/container-image-registry-htpasswd | base64 -d
        user-62hsyd:2JFqD8SJqYeLvecNdh3BvAFfKwhJF0De

    To get the registry pull spec exposed by a route:

        # oc get route -n sdi-observer container-image-registry -o jsonpath='{.spec.host}{"\n"}'
        container-image-registry-sdi-observer.apps.ocp.example.org

    To get the default ceritificate authority unless overridden by a parameter (requires jq of
    version 1.6 or higher):

        # oc get secret -n openshift-ingress-operator -o json router-ca | \
            jq -r '.data as $d | $d | keys[] | select(test("\\.crt$")) | $d[.]' | \
            base64 -d >router-ca.crt

    To verify the connection via a route:

        # curl -I --cacert ./router-ca.crt --user user-62hsyd:2JFqD8SJqYeLvecNdh3BvAFfKwhJF0De \
            https://container-image-registry-sdi-observer.apps.ocp.example.org/v2/
        HTTP/1.1 200 OK
        Content-Length: 2
        Content-Type: application/json; charset=utf-8
        Docker-Distribution-Api-Version: registry/2.0
        Date: Thu, 22 Apr 2021 13:26:26 GMT
        Set-Cookie: d22d6ce08115a899cf6eca6fd53d84b4=97c8742ee7d80fd9461b4b5afc1218f4; path=/; HttpOnly; Secure; SameSite=None
        Cache-control: private

    To list the images in the registry:

        # curl --silent --cacert ./router-ca.crt \
            --user user-62hsyd:2JFqD8SJqYeLvecNdh3BvAFfKwhJF0De \
            https://container-image-registry-sdi-observer.apps.ocp.example.org/v2/_catalog | jq
        {
          "repositories": [
            "com.sap.bds.docker/storagegateway",
            "com.sap.datahub.linuxx86_64/app-base",
            "com.sap.datahub.linuxx86_64/app-data",
        ...

    To check registry's storage usage:

        # oc rsh -n sdi-observer dc/container-image-registry df /var/lib/registry
        Filesystem  1K-blocks     Used Available Use% Mounted on
        10...60     125829120 28389376  97439744  23% /var/lib/registry
  |||,

  objects+: obssa { createdBy: regjobtmpl.createdBy }.Objects + bc.objects,

  parametersToExport+: [params.ReplacePersistentVolumeClaimsParam]
                       + params.RegistryDeployParams + params.RegistryParams + [
    params.ExposeWithLetsencryptParam,
  ] + bc.newParameters,
}
