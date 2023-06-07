# observer-operator
**DO NOT USE** yet!

// TODO(user): Add simple overview of use/purpose

## Description
// TODO(user): An in-depth paragraph about your project and overview of use

SDI Observer has been useful so far but prone to errors, hard to maintain, configure, test, install and update. The Operator is built using the well established Operator SDK making it easy to consume, configure and manage.

The Operator is supposed to replace SDI Observer once it reaches the same functionality level.

## Status

**alpha**

Implemented SDI Observer features:
- [x] vsystem route management
- [x] slcb route management
- [x] configure SDI nodes for kernal parameters
- [x] configure SDI nodes for container PID limits parameters
- [x] configure statefulset vsystem-vrep volume and volumemount
- [x] configure daemonset diagnostics-fluentd container privileges
- [x] configre host path mount for diagnostic pods
- [x] configure node selector on SDI and SLC Bridge namespace
- [x] configure role and rolebindings in SDI namespace
- 
Missing generic functionality:
- [] comprehensive SDIObserver status updates


## Getting Started
You’ll need a Kubernetes cluster to run against. You can use [KIND](https://sigs.k8s.io/kind) to get a local cluster for testing, or run against a remote cluster.
**Note:** Your controller will automatically use the current context in your kubeconfig file (i.e. whatever cluster `kubectl cluster-info` shows).

### Running on the cluster
1. Install Instances of Custom Resources:

```sh
kubectl apply -f config/samples/
```

2. Build and push your image to the location specified by `IMG`:
	
```sh
make docker-build docker-push IMG=<some-registry>/observer-operator:tag
```
	
3. Deploy the controller to the cluster with the image specified by `IMG`:

```sh
make deploy IMG=<some-registry>/observer-operator:tag
```

### Uninstall CRDs
To delete the CRDs from the cluster:

```sh
make uninstall
```

### Undeploy controller
UnDeploy the controller to the cluster:

```sh
make undeploy
```

## Contributing
// TODO(user): Add detailed information on how you would like others to contribute to this project

### How it works
This project aims to follow the Kubernetes [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)

It uses [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/) 
which provides a reconcile function responsible for synchronizing resources untile the desired state is reached on the cluster 

### Test It Out
1. Install the CRDs into the cluster:

```sh
make install
```

2. Run your controller (this will run in the foreground, so switch to a new terminal if you want to leave it running):

```sh
make run
```

**NOTE:** You can also run this in one step by running: `make install run`

### Modifying the API definitions
If you are editing the API definitions, generate the manifests such as CRs or CRDs using:

```sh
make manifests
```

**NOTE:** Run `make --help` for more information on all potential `make` targets

More information can be found via the [Kubebuilder Documentation](https://book.kubebuilder.io/introduction.html)

## Contributing

Requirements:
- Operator SDK 1.26
- go 1.19
- (for testing) OpenShift 4.8 clients and server

Setup:

    git clone github.com/redhat-sap/sap-data-intelligence
    cd sap-data-intelligence/observer-operator
    export GOPATH="$(pwd)/.go"
    export GOCACHE=""
    export GO111MODULE='on'
    export GOFLAGS=-mod=vendor
    go mod init $(pwd)

Test:

    make test

Build and push a new image:

    # # optionally, override DOCKER_CMD to e.g. docker
    make docker-build docker-push

The commands for creating the domain and API:

    operator-sdk init --domain sap-redhat.io --repo github.com/redhat-sap/sap-data-intelligence/observer-operator

    operator-sdk create api --group sdi --version v1alpha1 --kind SDIObserver --resource --controller 

## License

Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

