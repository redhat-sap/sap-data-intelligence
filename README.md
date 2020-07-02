# Work in Progress!!

SAP Data Intelligence 3.0 on OCP 4 to be supported soon.

Stay tuned.


## HOWTO

1. Get a secret for accessing registry.redhat.io at: https://access.redhat.com/terms-based-registry/
See [Red Hat Container Registry Authentication](https://access.redhat.com/RegistryAuthentication) for more information.

2. Create a project to host SDI Observer (e.g. `sdi-observer`): `oc new-project sdi-observer`

3. Create the downloaded secret in there and add it as a pull secret for builds:

        # oc create -f rht-registry-miminar-secret.yaml
        secret/1979710-miminar-pull-secret created
        # oc secrets link default 1979710-miminar-pull-secret --for=pull

4. Create the deployment files:

        # oc process NAMESPACE=sdi-observer SDI_NAMESPACE=sdi \
            REDHAT_REGISTRY_SECRET_NAME=1979710-miminar-pull-secret \
            DEPLOY_SDI_REGISTRY=true DEPLOY_LETSENCRYPT=true \
            -f observer/ocp-template.json | oc create -f -
            
## Update instructions
