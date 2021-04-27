# SDI Node Configurator

The template creates a daemonset that spawns pods on all matching nodes. The pods will
configure the nodes for running SAP Data Intelligence.

As of now, the configuration consists of loading kernel modules needed needed to use NFS
and manipulated iptables.

## Usage

Please run the node configurator in the same namespace as SDI Observer.

### Grant the needed permissions

Before running this template, Security Context Constraints need to be given to the
sdi-node-configurator service account. This can be achieved from command line with
system admin role with the following command:

  # oc adm policy add-scc-to-user -n $NAMESPACE privileged -z sdi-node-configurator

### Create the objects

Please make sure to set the NAMESPACE parameter to the namespace name of the SDI Observer.

    # oc process NAMESPACE=sdi \
        -f ../sap-data-intelligence/node-configurator/ocp-template.json
