In general, the installation of SAP Data Intelligence (SDI) follows these steps:

+ Install Red Hat OpenShift Container Platform
+ Configure the prerequisites for SAP Data Intelligence Foundation
+ Install SDI Observer
+ Install SAP Data Intelligence Foundation on OpenShift Container Platform

If you're interested in installation of SAP Data Hub or SAP Vora, please refer to the other installation guides:

- [SAP Data Hub 2 on OpenShift Container Platform 4](https://access.redhat.com/articles/4324391)
- [SAP Data Hub 2 on OpenShift Container Platform 3](https://access.redhat.com/articles/3630111)
- [Install SAP Data Hub 1.X Distributed Runtime on OpenShift Container Platform](https://access.redhat.com/articles/3451591)
- [Installing SAP Vora 2.1 on Red Hat OpenShift 3.7](https://access.redhat.com/articles/3299301)

**Note** OpenShift Container Storage (OCS) is called throughout this article under its new product name OpenShift Data Foundation (ODF).  
**Note** that OpenShift Container Platform (OCP) can be substituted by OpenShift Kubernetes Engine (OKE). OKE is sufficient and supported to run SAP Data Intelligence.

<span id="ftnt-security-disclaimer" markdown="1">**▲ Note**</span> There are known SAP image security issues that may be revealed during a security audit. Red Hat cannot resolve them. Please open a support case with SAP regarding any of the following:

- SAP containers run as root
- SAP containers run unconfined (unrestricted by SELinux)
- SAP containers require privileged security context

## 1. OpenShift Container Platform validation version matrix {#validation-version-matrix}

The following version combinations of SDI 2.X, OpenShift Container Platform (OCP), RHEL or RHCOS have been validated for the production environments:

SAP Data Intelligence | OpenShift Container Platform                                                                       | Operating System                                             | Infrastructure and (Storage)                                                                                                                                                                                                                                                                                                                                                                                                                                        | Confirmed&Supported by SAP
-----------           | ----------------------------                                                                       | -------------------------                                    | ----------------------------                                                                                                                                                                                                                                                                                                                                                                                                                                        | --------------------------
**3.0**               | **4.2** [**†**](#ftnt-no-longer-supported-by-rh)                                                   | **RHCOS** (nodes), **RHEL 8.1+** or Fedora (Management host) | VMware vSphere (*[ODF 4.2](https://docs.openshift.com/container-platform/4.2/storage/persistent_storage/persistent-storage-ocs.html)*)                                                                                                                                                                                                                                                                                                                              | supported [**†**](#ftnt-no-longer-supported-by-rh)
**3.0** Patch 3       | **4.2** [**†**](#ftnt-no-longer-supported-by-rh), **4.4** [**†**](#ftnt-no-longer-supported-by-rh) | **RHCOS** (nodes), **RHEL 8.2+** or Fedora (Management host) | VMware vSphere (*[ODF 4](https://docs.openshift.com/container-platform/4.4/storage/persistent_storage/persistent-storage-ocs.html)*)                                                                                                                                                                                                                                                                                                                                | supported [**†**](#ftnt-no-longer-supported-by-rh)
**3.0** Patch 4       | **4.4** [**†**](#ftnt-no-longer-supported-by-rh)                                                   | **RHCOS** (nodes), **RHEL 8.2+** or Fedora (Management host) | VMware vSphere (*[ODF 4](https://docs.openshift.com/container-platform/4.4/storage/persistent_storage/persistent-storage-ocs.html)*), (*[NetApp Trident 20.04](https://access.redhat.com/articles/5221421)*)                                                                                                                                                                                                                                                        | supported [**†**](#ftnt-no-longer-supported-by-rh)
**3.0** Patch 8       | **4.6**                                                                                            | **RHCOS** (nodes), **RHEL 8.2+** or Fedora (Management host) | KVM/libvirt (*[ODF 4](https://docs.openshift.com/container-platform/4.6/storage/persistent_storage/persistent-storage-ocs.html)*)                                                                                                                                                                                                                                                                                                                                   | supported
**3.1**               | **4.4** [**†**](#ftnt-no-longer-supported-by-rh)                                                   | **RHCOS** (nodes), **RHEL 8.3+** or Fedora (Management host) | VMware vSphere (*[ODF 4](https://docs.openshift.com/container-platform/4.6/storage/persistent_storage/persistent-storage-ocs.html)*)                                                                                                                                                                                                                                                                                                                                | not supported[**¹**](#ftnt-ocp-44-only-for-upgrade)
**3.1**               | **4.6**                                                                                            | **RHCOS** (nodes), **RHEL 8.3+** or Fedora (Management host) | VMware vSphere (*[ODF 4](https://docs.openshift.com/container-platform/4.6/storage/persistent_storage/persistent-storage-ocs.html)* [**¡**](#ftnt-ocs-min-version), *[NetApp Trident 20.10 + StorageGRID](https://access.redhat.com/articles/5221421)*), Bare metal [**∗**](#ftnt-baremetal-validated-configs) (*[ODF 4](https://docs.openshift.com/container-platform/4.6/storage/persistent_storage/persistent-storage-ocs.html)* [**¡**](#ftnt-ocs-min-version)) | supported
**3.2**               | **4.6**, **4.8**                                                                                   | **RHCOS** (nodes), **RHEL 8.3+** or Fedora (Management host) | VMware vSphere (*[ODF 4](https://docs.openshift.com/container-platform/4.8/storage/persistent_storage/persistent-storage-ocs.html)*                                                                                                                                                                                                                                                                                                                                 | supported
**3.2**               | **4.8**                                                                                            | **RHCOS** (nodes), **RHEL 8.3+** or Fedora (Management host) | Bare metal [**∗**](#ftnt-baremetal-validated-configs) (*[ODF 4](https://docs.openshift.com/container-platform/4.8/storage/persistent_storage/persistent-storage-ocs.html)* [**¡**](#ftnt-ocs-min-version))                                                                                                                                                                                                                                                          | supported

<span id="ftnt-no-longer-supported-by-rh" markdown="1">**†**</span> The referenced OpenShift release is no longer supported by Red Hat!  
<span id="ftnt-ocp-44-only-for-upgrade" markdown="1">**¹**</span> 3.1 on OpenShift 4.4 used to be supported by SAP only for the purpose of upgrade to OpenShift 4.6  
<span id="ftnt-baremetal-validated-configs" markdown="1">**∗**</span> Validated on two different hardware configurations:

- *(Dev/PoC level)* Lenovo 4 bare metal hosts setup composed of:

    - 3 schedulable control plane nodes running both ODF and SDI (Lenovo ThinkSystem SR530)
    - 1 compute node running SDI) (Lenovo ThinkSystem SR530)

  Note that this particular setup can be fully supported by Red Hat since OpenShift 4.8. On OpenShift 4.6, running ODF in [compact mode is still a Technology Preview](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.6/html-single/planning_your_deployment/index#compact-deployment-resource-requirements).

- *(Production level)* Dell Technologies bare metal cluster composed of:

    - 1 [*CSAH*](#ftnt-csah "Cluster System Admin Host") node (Dell EMC PowerEdge R640s)
    - 3 control plane nodes (Dell EMC PowerEdge R640s)
    - 3 dedicated ODF nodes (Dell EMC PowerEdge R640s)
    - 3 dedicated SDI nodes (Dell EMC PowerEdge R740xd)

  CSI supported external Dell EMC storage options and cluster sizing options available.  
  <span id="ftnt-csah" markdown="1">*CSAH*</span> stands for Cluster System Admin Host - an equivalent of *management host*

Please refer to the [compatibility matrix](#compatibility-matrix) for version combinations that are considered as working.

[SAP Note #2871970](https://launchpad.support.sap.com/#/notes/2871970) lists more details.

## 2. Requirements {#requirements}

### 2.1. Hardware/VM and OS Requirements {#hw-os-requirements}

#### 2.1.1. OpenShift Cluster {#openshift-cluster-requirements}

Make sure to consult the following official cluster requirements:

- of SAP Data Intelligence in SAP's documentation:
    - [Sizing Guide for SAP Data Intelligence (3.2)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.2.latest/en-US) / [(3.1)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.1.latest/en-US)
    - [Minimum sizing for SAP Data Intelligence (3.2)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.2.latest/en-US/d771891d749d425ba92603ec9b0084a8.html) / [(3.1)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.1.latest/en-US/d771891d749d425ba92603ec9b0084a8.html)
    - [Initial Sizing for SAP Data Intelligence (3.2)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.2.latest/en-US/a3aecc86834a4200a333246c2fdf2dab.html) / [(3.1)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.1.latest/en-US/a3aecc86834a4200a333246c2fdf2dab.html) / [T-Shirt Sizes for SAP Data Intelligence (3.0)](https://help.sap.com/viewer/835f1e8d0dde4954ba0f451a9d4b5f10/3.0.latest/en-US/adb8e6505e0c414faf57138b4cc6f075.html)
- of OpenShift 4 ([Minimum resource requirements (4.8)](https://docs.openshift.com/container-platform/4.8/installing/installing_bare_metal/installing-bare-metal.html#minimum-resource-requirements_installing-bare-metal) / [(4.6)](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal/installing-bare-metal.html#minimum-resource-requirements_installing-bare-metal))
- additionally, if deploying OpenShift Data Foundation (aka ODF), please consult also [ODF Supported configurations (4.8)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/planning_your_deployment/index#storage-cluster-deployment-approaches_rhocs) / [(4.6)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.6/html-single/planning_your_deployment/index#storage-cluster-deployment-approaches_rhocs)
- if deploying on VMware vSphere, please consider also [VMware vSphere infrastructure requirements (4.8)](https://docs.openshift.com/container-platform/4.8/installing/installing_vsphere/installing-vsphere.html#installation-vsphere-infrastructure_installing-vsphere) / [(4.6)](https://docs.openshift.com/container-platform/4.6/installing/installing_vsphere/installing-vsphere.html#installation-vsphere-infrastructure_installing-vsphere)
- if deploying NetApp Trident, please consult also [NetApp Hardware/VM and OS Requirements](https://access.redhat.com/articles/5221421#hw-os-requirements)

##### 2.1.1.1. Node Kinds {#openshift-cluster-node-kinds}

There are 4 kinds of nodes:

- *Bootstrap Node* - A temporary bootstrap node needed for the OpenShift deployment. The node can be either destroyed by the installer (using infrastructure-provisioned-installation -- aka IPI) or can be deleted manually by the administrator. Alternatively, it can be re-used as a worker node. Please refer to the [Installation process (4.8)](https://docs.openshift.com/container-platform/4.8/architecture/architecture-installation.html#installation-process_architecture-installation) / [(4.6)](https://docs.openshift.com/container-platform/4.6/architecture/architecture-installation.html#installation-process_architecture-installation) for more information.
- [*Master Nodes* (4.8)](https://docs.openshift.com/container-platform/4.8/architecture/control-plane.html#defining-masters_control-plane) / [(4.6)](https://docs.openshift.com/container-platform/4.6/architecture/control-plane.html#defining-masters_control-plane) - The control plane manages the OpenShift Container Platform cluster. The control plane can be made [schedulable](https://docs.openshift.com/container-platform/4.6/nodes/nodes/nodes-nodes-working.html#nodes-nodes-working-master-schedulable_nodes-nodes-working) to enable SDI workload there as well.
- [*Compute Nodes* (4.8)](https://docs.openshift.com/container-platform/4.8/architecture/control-plane.html#defining-workers_control-plane) / [(4.6)](https://docs.openshift.com/container-platform/4.6/architecture/control-plane.html#defining-workers_control-plane) - Run the actual workload (e.g. SDI pods). They are optional on a three-node cluster (where the master nodes are schedulable).
- [*ODF Nodes* (4.8)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/planning_your_deployment/index#ocs-architecture_rhocs) / [(4.6)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.6/html-single/planning_your_deployment/index#ocs-architecture_rhocs) - Run OpenShift Data Foundation (aka ODF). The nodes can be divided into *starting* (running both OSDs and monitors) and *additional* nodes (running only OSDs). Needed only when ODF shall be used as the backing storage provider.
    - **NOTE**: Running in a [compact mode](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/planning_your_deployment/index#compact-deployment-resource-requirements) (on control plane) is fully supported starting from ODF 4.8.
- *Management host* (aka *administrator's workstation* or *Jump host* - The Management host is used among other things for:

    - accessing the OpenShift cluster via a configured command line client (`oc` or `kubectl`)
    - configuring OpenShift cluster
    - running Software Lifecycle Container Bridge (SLC Bridge)

The hardware/software requirements for the *Management host* can be:

- **OS:** Red Hat Enterprise Linux 8.1+, RHEL 7.6+ or Fedora 30+
- **Diskspace:** 20GiB for `/`:

##### 2.1.1.2. Note a disconnected and air-gapped environments {#disconnected-explained}

By the term "disconnected host", it is referred to a host having no access to internet.  
By the term "disconnected cluster", it is referred to a cluster where each host is disconnected.  
A disconnected cluster can be managed from a *Management host* that is either connected (having access to the internet) or disconnected.
The latter scenario (both cluster and *management host* being disconnected) will be referred to by the term "air-gapped".
Unless stated otherwise, whatever applies to a disconnected host, cluster or environment, applies also to the "air-gapped".

##### 2.1.1.3. Minimum Hardware Requirements {#minimum-requirements}

The table below lists the *minimum* requirements and the minimum number of instances for each node type for the latest validated SDI and OpenShift 4.X releases. This is sufficient of a PoC (Proof of Concept) environments.

Type      | Count | Operating System         | vCPU [**⑃**](#ftnt-vcpu-vs-cpu) | RAM (GB) | Storage (GB) | [AWS Instance Type](https://aws.amazon.com/ec2/instance-types/)
-----     | ----- | ----------------         | -----                           | -------  | ------       | -----------------
Bootstrap | 1     | RHCOS                    | 4                               | 16       | 120          | m4.xlarge
Master    | 3     | RHCOS                    | 4                               | 16       | 120          | m4.xlarge
Compute   | 3+    | RHEL 7.8 or 7.9 or RHCOS | 8                               | 32       | 120          | m4.2xlarge

On a three-node cluster, it would look like this:

Type           | Count | Operating System | vCPU [**⑃**](#ftnt-vcpu-vs-cpu) | RAM (GB) | Storage (GB) | [AWS Instance Type](https://aws.amazon.com/ec2/instance-types/)
-----          | ----- | ---------------- | -----                           | -------  | ------       | -----------------
Bootstrap      | 1     | RHCOS            | 4                               | 16       | 120          | m4.xlarge
Master/Compute | 3     | RHCOS            | 10                              | 40       | 120          | m4.xlarge

If using ODF 4.6 in internal mode, at least additional 3 *(starting)* nodes are recommended. Alternatively, the Compute nodes outlined above can also run [**⑂**](#ftnt-compact-mode) ODF pods. In that case, the hardware specifications need to be extended accordingly. The following table lists the minimum requirements for each additional node:

Type                     | Count | Operating System | vCPU [**⑃**](#ftnt-vcpu-vs-cpu) | RAM (GB) | Storage (GB)                               | [AWS Instance Type](https://aws.amazon.com/ec2/instance-types/)
-----                    | ----- | ---------------- | -----                           | -------  | ------                                     | -----------------
ODF *starting* (OSD+MON) | 3     | RHCOS            | 10                              | 24       | 120 + 2048 [**♢**](#ftnt-ocs-requirements) | m5.4xlarge

##### 2.1.1.4. Minimum Production Hardware Requirements {#production-requirements}

The *minimum* production requirements for production systems for the latest validated SDI and OpenShift 4 are the following:

Type      | Count | Operating System         | vCPU [**⑃**](#ftnt-vcpu-vs-cpu) | RAM (GB) | Storage (GB) | [AWS Instance Type](https://aws.amazon.com/ec2/instance-types/)
-----     | ----- | ----------------         | -----                           | -------  | ------       | -----------------
Bootstrap | 1     | RHCOS                    | 4                               | 16       | 120          | m4.xlarge
Master    | 3+    | RHCOS                    | 8                               | 16       | 120          | c5.xlarge
Compute   | 3+    | RHEL 7.8 or 7.9 or RHCOS | 16                              | 64       | 120          | m4.4xlarge

On a three-node cluster, it would look like this:

Type           | Count | Operating System | vCPU [**⑃**](#ftnt-vcpu-vs-cpu) | RAM (GB) | Storage (GB) | [AWS Instance Type](https://aws.amazon.com/ec2/instance-types/)
-----          | ----- | ---------------- | -----                           | -------  | ------       | -----------------
Bootstrap      | 1     | RHCOS            | 4                               | 16       | 120          | m4.xlarge
Master/Compute | 3     | RHCOS            | 22                              | 72       | 120          | c5.9xlarge

If using ODF 4 in internal mode, at least additional 3 *(starting)* nodes are recommended. Alternatively, the Compute nodes outlined above can also run ODF [**⑂**](#ftnt-compact-mode) pods.  In that case, the hardware specifications need to be extended accordingly. The following table lists the minimum requirements for each additional node:

Type                     | Count | Operating System | vCPU [**⑃**](#ftnt-vcpu-vs-cpu) | RAM (GB) | Storage (GB)                                 | [AWS Instance Type](https://aws.amazon.com/ec2/instance-types/)
-----                    | ----- | ---------------- | -----                           | -------  | ------                                       | -----------------
ODF *starting* (OSD+MON) | 3     | RHCOS            | 20                              | 49       | 120 + 6×2048 [**♢**](#ftnt-ocs-requirements) | c5a.8xlarge

<span id="ftnt-ocs-requirements" markdown="1">**♢**</span> Please refer to [ODF Platform Requirements (4.8)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/planning_your_deployment/index#platform-requirements_rhocs) / [(4.6)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.6/html-single/planning_your_deployment/index#platform-requirements_rhocs).
<span id="ftnt-compact-mode" markdown="1">**⑂**</span> Running in a [compact mode](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/planning_your_deployment/index#compact-deployment-resource-requirements) (on control plane) is fully supported starting from ODF 4.8.  
<span id="ftnt-vcpu-vs-cpu" markdown="1">**⑃**</span> 1 physical core provides 2 vCPUs when hyper-threading is enabled. 1 physical core provides 1 vCPU when hyper-threading is not enabled.

### 2.2. Software Requirements {#sw-requirements}

#### 2.2.1. Compatibility Matrix {#compatibility-matrix}

Later versions of SAP Data Intelligence support newer versions of Kubernetes and OpenShift Container Platform or OpenShift Kubernetes Engine. Even if not listed in the [OpenShift validation version matrix above](#validation-version-matrix), the following version combinations are considered fully working and supported:

SAP Data Intelligence     | OpenShift Container Platform [**²**](#ftnt-oke) | Worker Node | Management host      | Infrastructure                                                   | Storage                                                                                                                                         | Object Storage
------------              | ---------------------------- | ----------- | -------------------- | --------------                                                   | -------                                                                                                                                         | --------------
**3.0 Patch 3 or higher** | **4.3**, **4.4**             | **RHCOS**   | RHEL 8.1 or newer    | Cloud [**❄**](#ftnt-cloud-providers), VMware vSphere             | *ODF 4*, *[NetApp Trident 20.04 or newer](https://access.redhat.com/articles/5221421)*, *vSphere volumes* [**♣**](#ftnt-lacking-object-storage) | *ODF*, *NetApp StorageGRID 11.3 or newer*
**3.0 Patch 8 or higher** | **4.4**, **4.5**, **4.6**    | **RHCOS**   | RHEL 8.1 or newer    | Cloud [**❄**](#ftnt-cloud-providers), VMware vSphere             | *ODF 4*, *[NetApp Trident 20.04 or newer](https://access.redhat.com/articles/5221421)*, *vSphere volumes* [**♣**](#ftnt-lacking-object-storage) | *ODF*, [*NetApp StorageGRID 11.3 or newer*](https://access.redhat.com/articles/5221421)
**3.1**                   | **4.4**, **4.5**, **4.6**    | **RHCOS**   | RHEL 8.1 or newer    | Cloud [**❄**](#ftnt-cloud-providers), VMware vSphere, Bare metal | *ODF 4*, *[NetApp Trident 20.04 or newer](https://access.redhat.com/articles/5221421)*, *vSphere volumes* [**♣**](#ftnt-lacking-object-storage) | *ODF* [**¡**](#ftnt-ocs-min-version), [*NetApp StorageGRID 11.4 or newer*](https://access.redhat.com/articles/5221421)
**3.2**                   | **4.6**, **4.7**, **4.8**    | **RHCOS**   | RHEL 8.1 or newer    | Cloud [**❄**](#ftnt-cloud-providers), VMware vSphere, Bare metal | *ODF 4*, *[NetApp Trident 20.04 or newer](https://access.redhat.com/articles/5221421)*, *vSphere volumes* [**♣**](#ftnt-lacking-object-storage) | *ODF* [**¡**](#ftnt-ocs-min-version), [*NetApp StorageGRID 11.4 or newer*](https://access.redhat.com/articles/5221421)

<span id="ftnt-oke" markdown="1">**²**</span> OpenShift Kubernetes Engine (OKE) is a viable and supported substiute for OpenShift Container Platform (OCP).  
<span id="ftnt-cloud-providers" markdown="1">**❄**</span> Cloud means any cloud provider supported by OpenShift Container Platform. For a complete list of tested and supported infrastructure platforms, please refer to [OpenShift Container Platform 4.x Tested Integrations](https://access.redhat.com/articles/4128421). The persistent storage in this case must be provided by the cloud provider. Please see refer to [Understanding persistent storage (4.8)](https://docs.openshift.com/container-platform/4.8/storage/understanding-persistent-storage.html#types-of-persistent-volumes_understanding-persistent-storage) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/understanding-persistent-storage.html#types-of-persistent-volumes_understanding-persistent-storage) for a complete list of supported storage providers.  
<span id="ftnt-lacking-object-storage" markdown="1">**♣**</span> This persistent storage provider does not offer a supported object storage service required by [SDI's checkpoint store](#prereq-checkpoint-store) and therefor is suitable only for SAP Data Intelligence development and PoC clusters. It needs to be complemented by an object storage solution for the full SDI functionality.  
<span id="ftnt-ocs-min-version" markdown="1">**¡**</span> For the full functionality (including SDI backup&restore), ODF 4.6.4 or newer is required. Alternatively, ODF external mode can be used while utilizing *RGW* for SDI backup&restore (checkpoint store).

Unless stated otherwise, the compatibility of a listed SDI version covers all its patch releases as well.

#### 2.2.2. Persistent Volumes {#prereq-ocp-pvs}

Persistent storage is needed for SDI. It is required to use storage that can be created dynamically. You can find more information in the [Understanding persistent storage (4.8)](https://docs.openshift.com/container-platform/4.8/storage/understanding-persistent-storage.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/understanding-persistent-storage.html) document.

#### 2.2.3. Container Image Registry {#prereq-container-image-registry}

The SDI installation requires a secured Image Registry where images are first mirrored from an SAP Registry and then delivered to the OpenShift cluster nodes. The integrated [OpenShift Container Registry (4.8)](https://docs.openshift.com/container-platform/4.8/registry/index.html#registry-integrated-openshift-registry_registry-overview) / [(4.6)](https://docs.openshift.com/container-platform/4.6/registry/index.html#registry-integrated-openshift-registry_registry-overview) is not appropriate for this purpose. Neither is AWS ECR Registry. For now, another image registry needs to be set up instead.

The requirements listed here is a subset of the official requirements listed in [Container Registry (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/946d67f312e74a13942f23e50aa06867.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/946d67f312e74a13942f23e50aa06867.html).

The word *secured* in this context means that the communication is encrypted using a TLS. Ideally with certificates signed by a trusted certificate authority. If the registry is also exposed publicly, it must require authentication and authorization in order to pull SAP images.

##### 2.2.3.1. Validated Registries {#prereq-validated-registries}

1. (*recommened*) Red Hat Quay 3.6 or higher is compatible with SAP Data Intelligence images and is supported for this purpose. The Quay registry can run either on OpenShift cluster itself, another OpenShift cluster or standalone. For more information, please see [Quay Registry for SAP DI](#apx-quay-for-sdi).

2. SDI Registry is a community-supported container image registry satisfying the requirements. Please refer to [Deploying SDI Registry](#apx-deploy-sdi-registry) for more information.

When finished you should have an external image registry up and running. We will use the URL `local.image.registry:5000` as an example. You can verify its readiness with the following command.

    # curl -k https://local.image.registry:5000/v2/
    {"errors":[{"code":"UNAUTHORIZED","message":"authentication required","detail":null}]}

#### 2.2.4. Checkpoint store enablement {#prereq-checkpoint-store}

In order to enable SAP Vora Database streaming tables, checkpoint store needs to be enabled. The store is an object storage on a particular storage back-end. Several back-end types are supported by the SDI installer that cover most of the storage cloud providers.

The enablement is strongly recommended for production clusters. Clusters having this feature disabled are suitable only for test, development or PoC use-cases.

Make sure to create a desired bucket before the SDI Installation. If the checkpoint store shall reside in a directory on a bucket, the directory needs to exist as well.

#### 2.2.5. SDI Observer {#prereq-sdi-observer}

Is a pod monitoring SDI's namespace and modifying objects in there that enable running of SDI on top of OpenShift. The observer shall be run in a dedicated namespace. It must be deployed before the SDI installation is started. [SDI Observer](#sdi-observer) section will guide you through the process of deployment.

## 3. Install Red Hat OpenShift Container Platform {#ocp-installation}

### 3.1. Prepare the Management host {#management-host-preparation}

**Note** the following has been tested on RHEL **8.4**. The steps shall be similar for other RPM based Linux distribution. Recommended are RHEL 7.7+, Fedora 30+ and CentOS 7+.

#### 3.1.1. Prepare the connected Management host  {#management-host-preparation-online}

1. Subscribe the *Management host* at least to the following repositories:

        # OCP_RELEASE=4.6
        # sudo subscription-manager repos                 \
            --enable=rhel-8-for-x86_64-appstream-rpms     \
            --enable=rhel-8-for-x86_64-baseos-rpms        \
            --enable=rhocp-${OCP_RELEASE:-4.6}-for-rhel-8-x86_64-rpms

2. Install `jq` binary. This installation guide has been tested with jq 1.6.

    - on RHEL 8, make sure `rhocp-4.6-for-rhel-8-x86_64-rpms` repository or newer is enabled and install it from there:

            # dnf install jq-1.6

    - on earlier releases or other distributions, download the binary from upstream:

            # sudo curl -L -O /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
            # sudo chmod a+x /usr/local/bin/jq

3. Download and install OpenShift client binaries.

        # sudo dnf install -y openshift-clients

#### 3.1.2. Prepare the disconnected RHEL Management host {#management-host-preparation-offline}

Please refer to [KB#3176811 Creating a Local Repository and Sharing With Disconnected/Offline/Air-gapped Systems](https://access.redhat.com/solutions/3176811) and [KB#29269 How can we regularly update a disconnected system (A system without internet connection)?](https://access.redhat.com/solutions/29269).

Install `jq-1.6` and `openshift-clients` from your local RPM repository.

### 3.2. Install OpenShift Container Platform {#install-openshift}

Install OpenShift Container Platform on your desired cluster hosts. Follow the [OpenShift installation guide (4.8)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.8/html/installing/index) / [(4.6)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.6/html/installing/index)

Several changes need to be done to the compute nodes running SDI workloads before SDI installation. These include:

1. pre-load needed kernel modules
2. increasing the PIDs limit of CRI-O container engine

They will be described in the next section.

### 3.3. OpenShift Post Installation Steps {#ocp-post-installation}

#### 3.3.1. *(optional)* Install OpenShift Data Foundation {#ocp-post-install-ocs}

Red Hat OpenShift Data Foundation (ODF) has been validated as the persistent storage provider for SAP Data Intelligence. Please refer to the [ODF documentation (4.8)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.8/html-single/installing/index) / [(4.6)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.6/html-single/installing/index)

Please make sure to read and follow [Disconnected Environment](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html/planning_your_deployment/disconnected-environment_rhocs) if you install on a disconnected cluster.

#### 3.3.2. *(optional)* Install NetApp Trident {#ocp-post-install-netapp}

NetApp Trident together with StorageGRID have been validated for SAP Data Intelligence and OpenShift. More details can be found at [SAP Data Intelligence on OpenShift 4 with NetApp Trident](https://access.redhat.com/articles/5221421#hw-os-requirements).

#### 3.3.3. Configure SDI compute nodes {#ocp-post-node-preparation}

Some SDI components require changes on the OS level of compute nodes. These could impact other workloads running on the same cluster. To prevent that from happening, it is recommended to dedicate a set of nodes to SDI workload. The following needs to be done:

1. Chosen nodes must be labeled e.g. using the `node-role.kubernetes.io/sdi=""` label.
2. MachineConfigs specific to SDI need to be created, they will be applied only to the selected nodes.
3. MachineConfigPool must be created to associate the chosen nodes with the newly created MachineConfigs.
    - no change will be done to the nodes until this point
4. *(optional)* Apply a node selector to `sdi`, `sap-slcbridge` and `datahub-system` projects.
    - SDI Observer can be configured to do that with `SDI_NODE_SELECTOR` parameter

Before modifying the recommended approach below, please make yourself familiar with the [custom pools concept](https://github.com/openshift/machine-config-operator/blob/master/docs/custom-pools.md) of the machine config operator.

##### 3.3.3.1. Air-gapped environment {#ocp-post-air-gapped}

If the *Management host* does not have access to the internet, you will need to clone the [sap-data-intelligence git repository](https://github.com/redhat-sap/sap-data-intelligence) to some other host and make it available on the *Management host*. For example:

    # cd /var/run/user/1000/usb-disk/
    # git clone https://github.com/redhat-sap/sap-data-intelligence

Then on the *Management host*:

- unless the local checkout already exists, copy it from the disk:

        # git clone /var/run/user/1000/usb-disk/sap-data-intelligence ~/sap-data-intelligence

- otherwise, re-apply local changes (if any) to the latest code:

        # cd ~/sap-data-intelligence
        # git stash         # temporarily remove local changes
        # git remote add drive /var/run/user/1000/usb-disk/sap-data-intelligence
        # git fetch drive
        # git merge drive   # apply the latest changes from drive to the local checkout
        # git stash pop     # re-apply the local changes on top of the latest code

##### 3.3.4.1. Label the compute nodes for SAP Data Intelligence {#ocp-post-label-nodes}

Choose compute nodes for the SDI workload and label them from the *Management host* like this:

    # oc label node/sdi-worker{1,2,3} node-role.kubernetes.io/sdi=""

##### 3.3.4.2. Pre-load needed kernel modules {#preload-kernel-modules-post}

To apply the desired changes to the existing and future SDI compute nodes, please create another machine config like this:

- *(connected management host)*

        # oc apply -f https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/snippets/mco/mc-75-worker-sap-data-intelligence.yaml

- *(disconnected management host)*

        # oc apply -f sap-data-intelligence/master/snippets/mco/mc-75-worker-sap-data-intelligence.yaml

<span id="ftnt-oc-apply-warning" markdown="1">**∇**</span> **NOTE**: If the warning below appears, it can be usually ignored. It suggests that the resource already exists on the cluster and has been created by none of the listed commands. In earlier versions of this documentation, plain `oc create` used to be recommended instead.

    Warning: oc apply should be used on resource created by either oc create --save-config or oc apply

##### 3.3.4.3. Change the maximum number of PIDs per Container {#change-pids-limit}

The process of configuring the nodes is described at [Modifying Nodes (4.8)](https://docs.openshift.com/container-platform/4.8/nodes/nodes/nodes-nodes-managing.html#nodes-nodes-managing-about_nodes-nodes-jobs) / [(4.6)](https://docs.openshift.com/container-platform/4.6/nodes/nodes/nodes-nodes-managing.html#nodes-nodes-managing-about_nodes-nodes-jobs)  In SDI case, the required settings are `.spec.containerRuntimeConfig.pidsLimit` in a `ContainerRuntimeConfig`. The result is a modified `/etc/crio/crio.conf` configuration file on each affected worker node with `pids_limit` set to the desired value. Please create a ContainerRuntimeConfig like this:

- *(connected management host)*

        # oc apply -f https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/snippets/mco/ctrcfg-sdi-pids-limit.yaml

- *(disconnected management host)*

        # oc apply -f sap-data-intelligence/master/snippets/mco/ctrcfg-sdi-pids-limit.yaml

##### 3.3.4.4. *(obsolete)* Enable net-raw capability for containers on schedulable nodes {#ocp-post-enable-net-raw-cap}

**NOTE**: Having effect only on OpenShift 4.6 or newer.  
**NOTE**: Shall be executed prior to OpenShift upgrade to 4.6 when running SDI already.  
**NOTE**: No longer necessary for SDI 3.1 Patch 1 or newer

Starting with OpenShift 4.6, `NET_RAW` capability is no longer granted to containers by default. Some SDI containers assume otherwise. To allow them to run on OpenShift 4.6, the following MachineConfig must be applied to the compute nodes:

*(connected management host)*

        # oc apply -f https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/snippets/mco/mc-97-crio-net-raw.yaml

*(disconnected management host)*

        # oc apply -f sap-data-intelligence/master/snippets/mco/mc-97-crio-net-raw.yaml

##### 3.3.4.4. Associate MachineConfigs to the Nodes {#ocp-post-mcp}

Define a new MachineConfigPool associating MachineConfigs to the nodes. The nodes will inherit all the MachineConfigs targeting `worker` and `sdi` roles.

- *(connected management host)*

        # oc apply -f https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/snippets/mco/mcp-sdi.yaml

- *(disconnected management host)*

        # oc apply -f sap-data-intelligence/master/snippets/mco/mcp-sdi.yaml

Note that you may see a warning [**∇**](#ftnt-oc-apply-warning) if the MCO exists already.

The changes will be rendered into `machineconfigpool/sdi`. The workers will be restarted one-by-one until the changes are applied to all of them. See [Applying configuration changes to the cluster (4.8)](https://github.com/openshift/machine-config-operator/tree/release-4.8#applying-configuration-changes-to-the-cluster) / [(4.6)](https://github.com/openshift/machine-config-operator/tree/release-4.6#applying-configuration-changes-to-the-cluster) for more information.

The following command can be used to wait until the change gets applied to all the worker nodes:

    # oc wait mcp/sdi --all --for=condition=updated

After performing the changes above, you should end up with a new role `sdi` assigned to the chosen nodes and a new MachineConfigPool containing the nodes:

    # oc get nodes
    NAME          STATUS   ROLES        AGE   VERSION
    ocs-worker1   Ready    worker       32d   v1.19.0+9f84db3
    ocs-worker2   Ready    worker       32d   v1.19.0+9f84db3
    ocs-worker3   Ready    worker       32d   v1.19.0+9f84db3
    sdi-worker1   Ready    sdi,worker   32d   v1.19.0+9f84db3
    sdi-worker2   Ready    sdi,worker   32d   v1.19.0+9f84db3
    sdi-worker3   Ready    sdi,worker   32d   v1.19.0+9f84db3
    master1       Ready    master       32d   v1.19.0+9f84db3
    master2       Ready    master       32d   v1.19.0+9f84db3
    master3       Ready    master       32d   v1.19.0+9f84db3

    # oc get mcp
    NAME     CONFIG                 UPDATED  UPDATING  DEGRADED  MACHINECOUNT  READYMACHINECOUNT  UPDATEDMACHINECOUNT  DEGRADED
    master   rendered-master-15f⋯   True     False     False     3             3                  3                    0
    sdi      rendered-sdi-f4f⋯      True     False     False     3             3                  3                    0
    worker   rendered-worker-181⋯   True     False     False     3             3                  3                    0

###### 3.3.4.4.1. Enable SDI on control plane {#ocp-post-enable-sdi-on-masters}

If the control plane (or master nodes) shall be used for running SDI workload, in addition to the previous step, one needs to perform the following:

1. Please make sure the [control plane is schedulable](https://docs.openshift.com/container-platform/4.6/nodes/nodes/nodes-nodes-working.html#nodes-nodes-working-master-schedulable_nodes-nodes-working)
2. Duplicate the machine configs for master nodes:

        # oc get -o json mc -l machineconfiguration.openshift.io/role=sdi | jq  '.items[] |
            select((.metadata.annotations//{}) |
                has("machineconfiguration.openshift.io/generated-by-controller-version") | not) |
            .metadata |= ( .name   |= sub("^(?<i>(\\d+-)*)(worker-)?"; "\(.i)master-") |
                           .labels |= {"machineconfiguration.openshift.io/role": "master"} )' | oc apply -f -

   Note that you may see a couple of warnings [**∇**](#ftnt-oc-apply-warning) if this has been done earlier.

3. Make the master machine config pool inherit the PID limits changes:

        # oc label mcp/master workload=sapdataintelligence

The following command can be used to wait until the change gets applied to all the worker nodes:

    # oc wait mcp/master --all --for=condition=updated

##### 3.3.4.6. Verification of the node configuration {#ocp-post-verify}

The following steps assume that the `node-role.kubernetes.io/sdi=""` label has been applied to nodes running the SDI workload. All the commands shall be executed on the *Management host*. All the diagnostics commands will be run in parallel on such nodes.

0. *(disconneted only)* Make one of the tools images available for your cluster:

    - Either use the image stream `openshift/tools`:

        1. Make sure the image stream has been populated:

                # oc get -n openshift istag/tools:latest

           Example output:

                NAME           IMAGE REFERENCE                                                UPDATED
                tools:latest   quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:13c...   17 hours ago

           If it is not the case, make sure your [registry mirror CA certificate is trusted](#ocp-configure-ca-trust).

        2. Set the following variable:

                # ocDebugArgs="--image-stream=openshift/tools:latest"

    - Or make `registry.redhat.io/rhel8/support-tools` image available in your local registry:

            # LOCAL_REGISTRY=local.image.registry:5000
            # podman login registry.redhat.io
            # podman login "$LOCAL_REGISTRY"    # if the local registry requires authentication
            # skopeo copy --remove-signatures \
                docker://registry.redhat.io/rhel8/support-tools:latest \
                docker://"$LOCAL_REGISTRY/rhel8/support-tools:latest"
            # ocDebugArgs="--image=$LOCAL_REGISTRY/rhel8/support-tools:latest"

1. Verify that the PID limit has been increased to 16384:

        # oc get nodes -l node-role.kubernetes.io/sdi= -o name | \
            xargs -P 6 -n 1 -i oc debug $ocDebugArgs {} -- chroot /host /bin/bash -c \
                "crio-status config | awk '/pids_limit/ {
                    print ENVIRON[\"HOSTNAME\"]\":\t\"\$0}'" |& grep pids_limit

   **NOTE**: `$ocDebugArgs` is set only in a disconnected environment, otherwise it shall be empty.

   An example output could look like this:

        sdi-worker3:    pids_limit = 16384
        sdi-worker1:    pids_limit = 16384
        sdi-worker2:    pids_limit = 16384

2. Verify that the kernel modules have been loaded:

        # oc get nodes -l node-role.kubernetes.io/sdi= -o name | \
            xargs -P 6 -n 1 -i oc debug $ocDebugArgs {} -- chroot /host /bin/sh -c \
                "lsmod | awk 'BEGIN {ORS=\":\t\"; print ENVIRON[\"HOSTNAME\"]; ORS=\",\"}
                    /^(nfs|ip_tables|iptable_nat|[^[:space:]]+(REDIRECT|owner|filter))/ {
                        print \$1
                    }'; echo" 2>/dev/null

   An example output could look like this:

        sdi-worker2:  iptable_filter,iptable_nat,xt_owner,xt_REDIRECT,nfsv4,nfs,nfsd,nfs_acl,ip_tables,
        sdi-worker3:  iptable_filter,iptable_nat,xt_owner,xt_REDIRECT,nfsv4,nfs,nfsd,nfs_acl,ip_tables,
        sdi-worker1:  iptable_filter,iptable_nat,xt_owner,xt_REDIRECT,nfsv4,nfs,nfsd,nfs_acl,ip_tables,

   If any of the following modules is missing on any of the SDI nodes, the module loading does not work: `iptable_nat`, `nfsv4`, `nfsd`, `ip_tables`, `xt_owner`

   To further debug missing modules, one can execute also the following command:

        # oc get nodes -l node-role.kubernetes.io/sdi= -o name | \
            xargs -P 6 -n 1 -i oc debug $ocDebugArgs {} -- chroot /host /bin/bash -c \
                 "( for service in {sdi-modules-load,systemd-modules-load}.service; do \
                     printf '%s:\t%s\n' \$service \$(systemctl is-active \$service); \
                 done; find /etc/modules-load.d -type f \
                     -regex '.*\(sap\|sdi\)[^/]+\.conf\$' -printf '%p\n';) | \
                 awk '{print ENVIRON[\"HOSTNAME\"]\":\t\"\$0}'" 2>/dev/null

   Please make sure that both systemd services are `active` and at least one `*.conf` file is listed for each host like shown in the following example output:

        sdi-worker3:  sdi-modules-load.service:       active
        sdi-worker3:  systemd-modules-load.service:   active
        sdi-worker3:  /etc/modules-load.d/sdi-dependencies.conf
        sdi-worker1:  sdi-modules-load.service:       active
        sdi-worker1:  systemd-modules-load.service:   active
        sdi-worker1:  /etc/modules-load.d/sdi-dependencies.conf
        sdi-worker2:  sdi-modules-load.service:       active
        sdi-worker2:  systemd-modules-load.service:   active
        sdi-worker2:  /etc/modules-load.d/sdi-dependencies.conf

3. *(obsolete)* Verify that the `NET_RAW` capability is granted by default to the pods:

        # # no longer needed for SDI 3.1 or newer
        # oc get nodes -l node-role.kubernetes.io/sdi= -o name | \
            xargs -P 6 -n 1 -i oc debug $ocDebugArgs {} -- /bin/sh -c \
                "find /host/etc/crio -type f -print0 | xargs -0 awk '/^[[:space:]]#/{next}
                    /NET_RAW/ {print ENVIRON[\"HOSTNAME\"]\":\t\"FILENAME\":\"\$0}'" |& grep NET_RAW

   An example output could look like:

        sdi-worker2:  /host/etc/crio/crio.conf.d/01-mc-defaultCapabilities:    default_capabilities = ["CHOWN", "DAC_OVERRIDE", "FSETID", "FOWNER", "NET_RAW", "SETGID", "SETUID", "SETPCAP", "NET_BIND_SERVICE", "SYS_CHROOT", "KILL"]
        sdi-worker2:  /host/etc/crio/crio.conf.d/90-default-capabilities:        "NET_RAW",
        sdi-worker1:  /host/etc/crio/crio.conf.d/90-default-capabilities:        "NET_RAW",
        sdi-worker1:  /host/etc/crio/crio.conf.d/01-mc-defaultCapabilities:    default_capabilities = ["CHOWN", "DAC_OVERRIDE", "FSETID", "FOWNER", "NET_RAW", "SETGID", "SETUID", "SETPCAP", "NET_BIND_SERVICE", "SYS_CHROOT", "KILL"]
        sdi-worker3:  /host/etc/crio/crio.conf.d/90-default-capabilities:        "NET_RAW",
        sdi-worker3:  /host/etc/crio/crio.conf.d/01-mc-defaultCapabilities:    default_capabilities = ["CHOWN", "DAC_OVERRIDE", "FSETID", "FOWNER", "NET_RAW", "SETGID", "SETUID", "SETPCAP", "NET_BIND_SERVICE", "SYS_CHROOT", "KILL"]

   Please make sure that at least one line is produced for each host.

#### 3.3.5. Deploy persistent storage provider {#deploy-persistent-storage-provider}

Unless your platform already offers a supported persistent storage provider, one needs to be deployed. Please refer to [Understanding persistent storage (4.8)](https://docs.openshift.com/container-platform/4.8/storage/understanding-persistent-storage.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/understanding-persistent-storage.html) for an overview of possible options.

On OpenShift, one can deploy [OpenShift Data Foundation (ODF) (4.8)](https://docs.openshift.com/container-platform/4.8/storage/persistent_storage/persistent-storage-ocs.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/persistent_storage/persistent-storage-ocs.html) running converged on OpenShift nodes providing both persistent volumes and object storage. Please refer to [ODF Planning your Deployment (4.8)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html/planning_your_deployment/index) / [(4.6)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.6/html/planning_your_deployment/index) and [Deploying OpenShift Data Foundation (4.8)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html/deploying_openshift_container_storage_on_vmware_vsphere/index) / [(4.6)](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.6/html/deploying_openshift_container_storage_on_vmware_vsphere/index) for more information and installation instructions.

ODF can be [deployed also in a disconnected environment](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html/planning_your_deployment/disconnected-environment_rhocs).

#### 3.3.6. Configure S3 access and bucket {#configure-s3}

Object storage is required for the following features of SDI:

- [backup&restore (previously checkpoint store) feature](#prereq-checkpoint-store) providing regular back-ups of SDI service data
- [SDL Data Lake connection (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/0ae3a716f81242f1a67a5c28db0d9939.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/0ae3a716f81242f1a67a5c28db0d9939.html) for the machine learning scenarios

Several interfaces to the object storage are supported by SDI. S3 interface is one of them. Please take a look at Checkpoint Store Type at [Required Input Parameters (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/abfa9c73f7704de2907ea7ff65e7a20a.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/abfa9c73f7704de2907ea7ff65e7a20a.html) for the complete list. SAP help page [covers preparation of object store (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/4c59231d8a8440db9b6a55b706c9026c.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/4c59231d8a8440db9b6a55b706c9026c.html).

Backup&restore can be enabled against ODF NooBaa's S3 endpoint as long as ODF is of version 4.6.4 or newer, or against RADOS Object Gateway S3 endpoint when ODF is deployed in the external mode.

##### 3.3.6.1. Using NooBaa or RADOS Object Gateway S3 endpoint as object storage {#configure-s3-with-noobaa}

ODF contains [NooBaa object data service for hybrid and multi cloud environments](https://www.openshift.com/blog/introducing-multi-cloud-object-gateway-for-openshift) which provides S3 API one can use with SAP Data Intelligence. Starting from ODF release 4.6.4, it can be used also for SDI's backup&restore functionality. Alternatively, the functionality can be enabled against RADOS Object Gateway S3 endpoint (from now on just *RGW*) which is available when ODF is deployed in the [external mode](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/planning_your_deployment/index#external_approach).

For SDI, one needs to provide the following:

- S3 host URL prefixed either with `https://` or `http://`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- bucket name

**NOTE**: In case of `https://`, the endpoint must be secured by certificates signed by a trusted certificate authority. Self-signed CAs will not work out of the box as of now.

Once ODF is deployed, one can create the access keys and buckets using one of the following:

- *(internal mode only)* via NooBaa Management Console by default exposed at `noobaa-mgmt-openshift-storage.apps.<cluster_name>.<base_domain>`
- *(both internal and external modes)* via CLI with [`mksdibuckets` script](https://github.com/redhat-sap/sap-data-intelligence/blob/master/utils/mksdibuckets)

In both cases, the S3 endpoint provided to the SAP Data Intelligence cannot be secured with a self-signed certificate as of now. Unless the endpoints are secured with a proper signed certificate, one must use insecure HTTP connection. Both NooBaa and *RGW* come with such an insecure service reachable from inside the cluster (within the SDN), it cannot be resolved from outside of cluster unless [exposed via e.g. route](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html-single/managing_hybrid_and_multicloud_resources/index#Accessing-the-RADOS-Object-Gateway-S3-endpoint_rhocs).

The following two URLs are the example endpoints on OpenShift cluster with ODF deployed.

1. `http://s3.openshift-storage.svc.cluster.local` - NooBaa S3 Endpoint available always
2. `http://rook-ceph-rgw-ocs-external-storagecluster-cephobjectstore.openshift-storage.svc.cluster.local:8080` - *RGW* endpoint that shall be preferably used when ODF is deployed in the external mode

For ODF 4.6.4 or *older*, enable SDI's backup&restore functionality, one must use the one with `rgw` in its name.

###### 3.3.6.1.1. Creating an S3 bucket using CLI {#noobaa-create-bucket}

The bucket can be created with the command below executed from the *Management host*. Be sure to switch to appropriate project/namespace (e.g. `sdi`) first before executing the following command or append parameters `-n SDI_NAMESPACE` to it.

- *(connected management host)*

        # bash <(curl -s https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/utils/mksdibuckets)

- *(disconnected management host)*

        # bash sap-data-intelligence/master/utils/mksdibuckets

By default, two buckets will be created. You can list them this way:

- *(connected management host)*

        # bash <(curl -s https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/utils/mksdibuckets) list

- *(disconnected management host)*

        # bash sap-data-intelligence/master/utils/mksdibuckets list

Example output:

    Bucket claim namespace/name:  sdi/sdi-checkpoint-store  (Status: Bound, Age: 7m33s)
      Cluster internal URL:       http://s3.openshift-storage.svc.cluster.local
      Bucket name:                sdi-checkpoint-store-ef4999e0-2d89-4900-9352-b1e1e7b361d9
      AWS_ACCESS_KEY_ID:          LQ7YciYTw8UlDLPi83MO
      AWS_SECRET_ACCESS_KEY:      8QY8j1U4Ts3RO4rERXCHGWGIhjzr0SxtlXc2xbtE
    Bucket claim namespace/name:  sdi/sdi-data-lake  (Status: Bound, Age: 7m33s)
      Cluster internal URL:       http://s3.openshift-storage.svc.cluster.local
      Bucket name:                sdi-data-lake-f86a7e6e-27fb-4656-98cf-298a572f74f3
      AWS_ACCESS_KEY_ID:          cOxfi4hQhGFW54WFqP3R
      AWS_SECRET_ACCESS_KEY:      rIlvpcZXnonJvjn6aAhBOT/Yr+F7wdJNeLDBh231

    # # NOTE: for more information and options, run the command with --help

The example above uses ODF NooBaa's S3 endpoint which is always the preferred choice for ODF internal mode.

The values of the claim `sdi-checkpoint-store` shall be passed to the following SLC Bridge parameters during [SDI's installation](#sdi-install) in order to enable backup&restore (previously known as) checkpoint store functionality.

Parameter                      | Example value
---------                      | -------------
Object Store Type              | `S3 compatible object store`
Access Key                     | `LQ7YciYTw8UlDLPi83MO`
Secret Key                     | `8QY8j1U4Ts3RO4rERXCHGWGIhjzr0SxtlXc2xbtE`
Endpoint                       | `http://s3.openshift-storage.svc.cluster.local`
Path                           | `sdi-checkpoint-store-ef4999e0-2d89-4900-9352-b1e1e7b361d9`
Disable Certificate Validation | Yes

###### 3.3.6.1.2. Increasing object bucket limits {#rgw-increase-bucket-limits}

**NOTE**: needed only for *RGW* (ODF external mode)

When performing checkpoint store validation during SDI installation, the installer will create a temporary bucket. For that to work with the *RGW*, bucket's owner limit on maximum allocatable buckets needs to be increased. The limit is set to 1 by default.

You can use the following command to perform the needed changes for the bucket assigned to the backup&restore (checkpoint store). Please execute it on the management node of the external Red Hat Ceph Storage cluster (or on the host where the external *RGW* service runs). The last argument is the "Bucket name", not the "Bucket claim name".

- *(connected management host)*

        # bash <(curl -s https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/utils/rgwtunebuckets) \
                sdi-checkpoint-store-ef4999e0-2d89-4900-9352-b1e1e7b361d9

- *(disconnected management host)*

        # bash sap-data-intelligence/master/utils/rgwtunebuckets \
                sdi-checkpoint-store-ef4999e0-2d89-4900-9352-b1e1e7b361d9

For more information and additional options, append `--help` parameter at the end.

#### 3.3.7. Set up a Container Image Registry {#setup-image-registry}

If you haven't done so already, please follow the [Container Image Registry prerequisite](#prereq-container-image-registry).

**NOTE**: It is now required to use a registry secured by TLS for SDI. Plain `HTTP` will not do.

If the registry is signed by a proper trusted (not self-signed) certificate, this may be skipped.

There are two ways to make OpenShift trust an additional registry using certificates signed by a self-signed certificate authority:

- *(recommended)* [update the CA certificate trust in OpenShift's image configuration](#ocp-configure-ca-trust).
- *(less secure)* [mark the registry as insecure](#ocp-configure-insecure-registry)

#### 3.3.8. Configure the OpenShift Cluster for SDI {#configure-the-openshift-cluster-for-sap-vora}

##### 3.3.8.1. Becoming a cluster-admin {#becoming-cluster-admin}

Many commands below require *cluster admin* privileges. To become a *cluster-admin*, you can do one of the following:

- Use the `auth/kubeconfig` generated in the working directory during the installation of the OpenShift cluster:

        INFO Install complete!
        INFO Run 'export KUBECONFIG=<your working directory>/auth/kubeconfig' to manage the cluster with 'oc', the OpenShift CLI.
        INFO The cluster is ready when 'oc login -u kubeadmin -p <provided>' succeeds (wait a few minutes).
        INFO Access the OpenShift web-console here: https://console-openshift-console.apps.demo1.openshift4-beta-abcorp.com
        INFO Login to the console with user: kubeadmin, password: <provided>
        # export KUBECONFIG=working_directory/auth/kubeconfig
        # oc whoami
        system:admin

- As a `system:admin` user or a member of `cluster-admin` group, make another user a cluster admin to allow him to perform the SDI installation:

    1. As a *cluster-admin*, [configure the authentication (4.8)](https://docs.openshift.com/container-platform/4.8/authentication/understanding-identity-provider.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/authentication/understanding-identity-provider.html) and add the desired user (e.g. `sdiadmin`).
    2. As a *cluster-admin*, grant the user a permission to administer the cluster:

            # oc adm policy add-cluster-role-to-user cluster-admin sdiadmin

You can learn more about the *cluster-admin* role in [Cluster Roles and Local Roles article (4.8)](https://docs.openshift.com/container-platform/4.8/authentication/using-rbac.html#default-roles_using-rbac) / [(4.6)](https://docs.openshift.com/container-platform/4.6/authentication/using-rbac.html#default-roles_using-rbac)

## 4. SDI Observer {#sdi-observer}

SDI Observer monitors SDI and SLC Bridge namespaces and applies changes to SDI deployments to allow SDI to run on OpenShift. Among other things, it does the following:

- adds additional persistent volume to `vsystem-vrep` StatefulSet to allow it to run on RHCOS system
- grants fluentd pods permissions to logs
- reconfigures the fluentd pods to parse plain text file container logs on the OpenShift 4 nodes
- exposes SDI System Management service
- exposes SLC Bridge service
- *(optional)* deploys the [SDI Registry](#apx-deploy-sdi-registry) suitable for mirroring, storing and serving SDI images and for use by the Pipeline Modeler
- *(optional)* creates `cmcertificates` secret to allow SDI to talk to container image registry secured by a self-signed CA certificate early during the installation time

It is deployed as an OpenShift template. Its behaviour is controlled by the template's parameters which are mirrored to its environment variables.

Deploy SDI Observer in its own k8s namespace (e.g. `sdi-observer`). Please refer to [its documentation](https://github.com/redhat-sap/sap-data-intelligence/tree/master/observer) for the complete list of issues that it currently attempts to solve.

### 4.1. Prerequisites {#sdi-observer-prereq}

The following must be satisfied before SDI Observer can be deployed:

- OpenShift cluster must be healthy including all the cluster operators.
- The [OpenShift integrated image registry](https://docs.openshift.com/container-platform/4.8/registry/configuring-registry-operator.html) must be properly configured and working.

#### 4.2.1. Prerequisites for Connected OpenShift Cluster {#sdi-observer-prereq-online}

In order to build images needed for SDI Observer, a secret with credentials for `registry.redhat.io` needs to be created in the namespace of SDI Observer. Please visit [Red Hat Registry Service Accounts](https://access.redhat.com/terms-based-registry/) to obtain the OpenShift secret. For more details, please refer to [Red Hat Container Registry Authentication](https://access.redhat.com/RegistryAuthentication). We will refer to the file as`rht-registry-secret.yaml`. The import to the OpenShift cluster will be covered down below.

#### 4.2.2. Prerequisites for a Disconnected OpenShift Cluster {#sdi-observer-prereq-offline}

On a disconnected OpenShift cluster, it is necessary to mirror a pre-built image of SDI Observer to a local container image registry. Please follow [Disconnected OpenShift cluster instructions](https://github.com/redhat-sap/sap-data-intelligence/tree/master/observer#user-content-disconnected-ocp-cluster).

#### 4.2.3. Instantiation of Observer's Template {#sdi-observer-instantiate}

Assuming the SDI will be run in the `SDI_NAMESPACE` which is different from the observer `NAMESPACE`, instantiate the template with default parameters like this:

1. Prepare the script and images depending on your system connectivity.

    - In a connected environment, download the run script from git repository like this:

            # curl -O https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/observer/run-observer-template.sh

    - In a disconnected environment, where the *Management host* is *connected*.

      Mirror the SDI Observer image to the local registry. For example, on RHEL8:

            # podman login local.image.registry:5000    # if the local registry requires authentication
            # skopeo copy \
                docker://quay.io/redhat-sap-cop/sdi-observer:latest-ocp4.8 \
                docker://local.image.registry:5000/sdi-observer:latest-ocp4.8

      Please make sure to modify the `4.8` suffix according to your OpenShift server minor release.

    - In an air-gapped environment (assuming the [observer repository has been already cloned to the *Management host*](#ocp-post-air-gapped)):

        1. On a host with access to the internet, copy the SDI Observer image to an archive on USB drive. For example, on RHEL8:

                # skopeo copy \
                    docker://quay.io/redhat-sap-cop/sdi-observer:latest-ocp4.8 \
                    oci-archive:/var/run/user/1000/usb-disk/sdi-observer.tar:latest-ocp4.8

        2. Plug the USB drive to the *Management host* (without internet access) and mirror the image from it to your `local.image.registry:5000`:

                # skopeo copy \
                    oci-archive:/var/run/user/1000/usb-disk/sdi-observer.tar:latest-ocp4.8 \
                    docker://local.image.registry:5000/sdi-observer:latest-ocp4.8

2. Edit the downloaded `run-observer-template.sh` file in your favorite editor. Especially, mind the `FLAVOUR`, `NAMESPACE` and `SDI_NAMESPACE` parameters.

    - for the `ubi-build` flavour, make sure to set `REDHAT_REGISTRY_SECRET_PATH=to/your/rht-registry-secret.yaml` downloaded [earlier](#sdi-observer-prereq-online)
    - for a disconnected environment, make sure to set `FLAVOUR` to `ocp-prebuilt` and `IMAGE_PULL_SPEC` to your `local.image.registry:5000`
    - for an air-gapped environment, set also `SDI_OBSERVER_REPOSITORY=to/local/git/repo/checkout`

3. Run it in bash like this:

        # bash ./run-observer-template.sh

4. Keep the modified script around for case of updates.

#### 4.2.4. SDI Observer Registry {#sdi-observer-registry}

**NOTE:** SDI Observer can optionally deploy SDI Registry on a *connected* OpenShift cluster only. For a *disconnected* environment, please refer to [Generic instantiation for a disconnected environment](#apx-deploy-sdi-registry-disconnected).

If the observer is configured to deploy SDI Registry via `DEPLOY_SDI_REGISTRY=true` parameter, it will deploy the `deploy-registry` job which does the following:

1. (*connected only*) builds the `container-image-registry` image and pushes it to the integrated OpenShift Image Registry
2. generates or uses configured credentials for the registry
3. deploys `container-image-registry` deployment config which in turn deploys a corresponding pod
4. exposes the registry using a route

    - if observer's `SDI_REGISTRY_ROUTE_HOSTNAME` parameter is set, it will be used as its hostname
    - otherwise the registry's hostname will be `container-image-registry-${NAMESPACE}.apps.<cluster_name>.<base_domain>`

##### 4.2.4.1. SDI Registry Template parameters {#sdi-observer-registry-parameters}

The following Observer's Template Parameters influence the deployment of the SDI Registry:

Parameter                           | Example value                 | Description
---------                           | -------------                 | -----------
`DEPLOY_SDI_REGISTRY`               | `true`                        | Whether to deploy SDI Registry for the purpose of SAP Data Intelligence.
`REDHAT_REGISTRY_SECRET_NAME`       | `123456-username-pull-secret` | Name of the secret with credentials for registry.redhat.io registry. Please visit  Please visit [Red Hat Registry Service Accounts](https://access.redhat.com/terms-based-registry/) to obtain the OpenShift secret. For more details, please refer to [Red Hat Container Registry Authentication](https://access.redhat.com/RegistryAuthentication). Must be provided in order to build registry's image.
`SDI_REGISTRY_ROUTE_HOSTNAME`                          | `registry.cluster.tld`        | This variable will be used as the SDI Registry's hostname when creating the corresponding route. Defaults to `container-image-registry-$NAMESPACE.<cluster_name>.<base_domain>`. If set, the domain name must resolve to the IP of the ingress router.
`INJECT_CABUNDLE`                   | `true`                        | Inject CA certificate bundle into SAP Data Intelligence pods. The bundle can be specified with `CABUNDLE_SECRET_NAME`. It is needed if the registry is secured by a self-signed certificate.
`CABUNDLE_SECRET_NAME`              | `custom-ca-bundle`            | The name of the secret containing certificate authority bundle that shall be injected into Data Intelligence pods. By default, the secret bundle is obtained from `openshift-ingress-operator` namespace where the `router-ca` secret contains the certificate authority used to sign all the edge and reencrypt routes that are, among others, used for `SDI_REGISTRY` and S3 API services. The secret name may be optionally prefixed with `$namespace/`.
`SDI_REGISTRY_STORAGE_CLASS_NAME`   | `ocs-storagecluster-cephfs`   | Unless given, the default storage class will be used. If possible, prefer volumes with `ReadWriteMany` (`RWX`) access mode.
`REPLACE_SECRETS`                   | `true`                        | By default, existing `SDI_REGISTRY_HTPASSWD_SECRET_NAME` secret will not be replaced if it already exists. If the registry credentials shall be changed while using the same secret name, this must be set to `true`.
`SDI_REGISTRY_AUTHENTICATION`       | `none`                        | Set to `none` if the registry shall not require any authentication at all. The default is to secure the registry with `htpasswd` file which is necessary if the registry is publicly available (e.g. when exposed via ingress route which is globally resolvable).
`SDI_REGISTRY_USERNAME`             | `registry-user`               | Will be used to generate htpasswd file to provide authentication data to the sdi registry service as long as `SDI_REGISTRY_HTPASSWD_SECRET_NAME` does not exist or `REPLACE_SECRETS` is `true`. Unless given, it will be autogenerated by the job.
`SDI_REGISTRY_PASSWORD`             | `secure-password`             | ditto
`SDI_REGISTRY_HTPASSWD_SECRET_NAME` | `registry-htpasswd`           | A secret with htpasswd file with authentication data for the sdi image container. If given and the secret exists, it will be used instead of `SDI_REGISTRY_USERNAME` and `SDI_REGISTRY_PASSWORD`. Defaults to `container-image-registry-htpasswd`. Please make sure to follow [the official guidelines on generating the `htpasswd` file](https://docs.docker.com/registry/configuration/#htpasswd).
`SDI_REGISTRY_VOLUME_CAPACITY`      | `250Gi`                       | Volume space available for container images. Defaults to `120Gi`.
`SDI_REGISTRY_VOLUME_ACCESS_MODE`   | `ReadWriteMany`               | If the given `SDI_REGISTRY_STORAGE_CLASS_NAME` or the default storage class supports `ReadWriteMany` ("RWX") access mode, please change this to `ReadWriteMany`. For example, the `ocs-storagecluster-cephfs` storage class, deployed by ODF operator, does support it.

To use them, please set the desired parameters in the `run-observer-template.sh` script in the [section above](#sdi-observer-instantiate).

**Monitoring registry's deployment**

    # oc logs -n "${NAMESPACE:-sdi-observer}" -f job/deploy-registry

You can find more information in the appendix:
- [Update instructions](#apx-deploy-sdi-registry-tmpl-run)
- [Determine Registry's credentials](#apx-deploy-sdi-registry-get-credentials)
- [Verification](#apx-deploy-sdi-registry-verification)

### 4.3. Managing SDI Observer {#sdi-observer-manage}

#### 4.3.1. Viewing and changing the current configuration {#sdi-observer-configure}

View the current configuration of SDI Observer:

    # oc set env --list -n "${NAMESPACE:-sdi-observer}" dc/sdi-observer

Change the settings:

- it is recommended to modify the [run-observer-template.sh and re-run it](#sdi-observer-instantiate)
- it is also possible to set the desired parameter directly without triggering an image build:

        # # instruct the observer to schedule SDI pods only on the matching nodes
        # oc set env -n "${NAMESPACE:-sdi-observer}" dc/sdi-observer SDI_NODE_SELECTOR="node-role.kubernetes.io/sdi="

#### 4.3.2. Re-deploying SDI Observer {#sdi-observer-redeploy}

Is useful in the following cases:

- SDI Observer shall be updated to the latest release.
- SDI has been uninstalled and its namespace deleted and/or re-created.
- Parameter being reflected in multiple resources (not just in the DeploymentConfig) needs to be changed (e.g. `OCP_MINOR_RELEASE`)
- Different SDI instance in another namespace shall be observed.

Before updating to the latest SDI Observer code, please be sure to check the [Update instructions](https://github.com/redhat-sap/sap-data-intelligence/blob/master/observer/README.adoc#update-instructions).

**NOTE**: Re-deployment preserves generated secrets and persistent volumes unless `REPLACE_SECRETS` or `REPLACE_PERSISTENT_VOLUMES` are `true`.

1. Backup the previous `run-observer-template.sh` script and open it as long as available. If not available, run the following to see the previous environment variables:

        # oc set env --list dc/sdi-observer -n "${NAMESPACE:-sdi-observer}"

2. Download the run script from git repository like this:

        # curl -O https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/observer/run-observer-template.sh

3. Edit the downloaded `run-observer-template.sh` file in your favorite editor. Especially, mind the `FLAVOUR`, `NAMESPACE`, `SDI_NAMESPACE` and `OCP_MINOR_RELEASE` parameters. Compare it against the old `run-observer-template.sh` or against the output of `oc set env --list dc/sdi-observer` and update the parameters accordingly.

4. Run it in bash like this:

        # bash ./run-observer-template.sh

5. Keep the modified script around for case of updates.

## 5. Install SDI on OpenShift {#sdi-install}

### 5.1. Install Software Lifecycle Container Bridge {#sdi-slcb}

Please follow the [official documentation (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/0986e8da1d8f43379be9c7999f9ff280.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/0986e8da1d8f43379be9c7999f9ff280.html).

#### 5.1.1. Important Parameters {#sdi-slcb-parameters}

Parameter                                 | Condition                                          | Description
---------                                 | ---------                                          | -----------
Mode                                      | Always                                             | Make sure to choose the `Expert` Mode.
Address of the Container Image Repository | Always                                             | This is the `Host` value of the `container-image-registry` route in the observer namespace if the registry is deployed by SDI Observer.
Image registry username                   | if … [**‡**](#ftnt-param-registry-auth)            | Refer to your registry configuration. If using the SDI Registry, please follow [Determine Registry's credentials](#apx-deploy-sdi-registry-get-credentials).
Image registry password                   | if … [**‡**](#ftnt-param-registry-auth)            | ditto
Namespace of the SLC Bridge               | Always                                             | If you override the default (`sap-slcbridge`), make sure to [deploy SDI Observer](#sdi-observer-instantiate) with the corresponding `SLCB_NAMESPACE` value.
Service Type                              | SLC Bridge Base installation                       | On vSphere, make sure to use `NodePort`. On AWS, please use `LoadBalancer`.
Cluster No Proxy                          | Required in conjunction with the HTTPS Proxy value | Make sure to this according to the [Configuring HTTP Proxy for the SLC Bridge](#apx-http-proxy-slcb) section.

<span id="ftnt-param-registry-auth" markdown="1">**‡**</span> If the registry requires authentication. [Red Hat Quay](#apx-quay-for-sdi) or [SDI Registry](#apx-deploy-sdi-registry) does.

For more details, please refer to [Configuring the cluster-wide proxy (4.8)](https://docs.openshift.com/container-platform/4.8/networking/enable-cluster-wide-proxy.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/networking/enable-cluster-wide-proxy.html)

On a NAT'd on-premise cluster, in order to access `slcbridgebase-service` `NodePort` service, one needs to have either a direct access to one of the SDI Compute nodes or modify an external load balancer to add an additional route to the service.

#### 5.1.2. Install SLC Bridge {#sdi-slcb-install}

Please install SLC Bridge according to [Making the SLC Bridge Base available on Kubernetes (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/8ae38791d71046fab1f25ee0f682dc4c.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/8ae38791d71046fab1f25ee0f682dc4c.html) while paying attention to the notes on the [installation parameters](#sdi-slcb-parameters).

##### 5.1.2.1. Exposing SLC Bridge with OpenShift Ingress Controller {#sdi-slcb-ingress}

For SLC Bridge, the only possible type of TLS termination is `passthrough` unless the Ingress Controller is configured to use globally trusted certificates.

It is recommended to let the SDI Observer (0.1.15 at the minimum) to manage the route creation and updates. If the SDI Observer has been deployed with `MANAGE_SLCB_ROUTE=true`, this section can be skipped. To configure it ex post, please execute the following:

    # oc set env -n "${NAMESPACE:-sdi-observer}" dc/sdi-observer MANAGE_SLCB_ROUTE=true
    # # wait for the observer to get re-deployed
    # oc rollout status -n "${NAMESPACE:-sdi-observer}" -w dc/sdi-observer

After a while, the bridge will be become available at `https://sap-slcbridge.apps.<cluster_name>.<base_domain>/docs/index.html`. You can wait for route's availability like this:

    # oc get route -w -n "${SLCB_NAMESPACE:-sap-slcbridge}"
    NAME            HOST/PORT                                         PATH   SERVICES                PORT    TERMINATION            WILDCARD
    sap-slcbridge   <SLCB_NAMESPACE>.apps.<cluster_name>.<base_domain>       slcbridgebase-service   <all>   passthrough/Redirect   None

###### 5.1.2.1.1. Manually exposing SLC Bridge with Ingress {#sdi-slcb-ingress-manual}

Alternatively, you can expose SLC Bridge manually with this approach.

1. Look up the `slcbridgebase-service` service:

        # oc project "${SLCB_NAMESPACE:-sap-slcbridge}"            # switch to the Software Lifecycle Bridge project
        # oc get services | grep 'NAME\|slcbridge'
        NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)           AGE
        slcbridgebase-service   NodePort    172.30.206.105   <none>        32455:31477/TCP   14d

2. Create the route for the service:

        # oc create route passthrough sap-slcbridge --service=slcbridgebase-service \
            --insecure-policy=Redirect --dry-run=client -o json | \
            oc annotate --local -f - haproxy.router.openshift.io/timeout=10m -o json | oc apply -f -

   You can also set your desired hostname with the `--hostname` parameter. Make sure it resolves to the router's IP.

3. Get the generated hostname:

        # oc get route
        NAME      HOST/PORT                                                  PATH  SERVICES  PORT      TERMINATION           WILDCARD
        vsystem   vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>        vsystem   vsystem   passthrough/Redirect  None

4. Make sure to configure your external load balancer to increase the timeout for WebSocket connections for this particular hostname at least to 10 minutes. For example, in HAProxy, it would be `timeout tunnel 10m`.

5. Access the System Management service at `https://vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>` to verify.

##### 5.1.2.2. Using an external load balancer to access SLC Bridge's NodePort {#sdi-slcb-lb}

**NOTE**: applicable only when "Service Type" was set to "NodePort".

Once the SLC Bridge is deployed, its `NodePort` shall be determined in order to point the load balancer at it.

    # oc get svc -n "${SLCB_NAMESPACE:-sap-slcbridge}" slcbridgebase-service -o jsonpath='{.spec.ports[0].nodePort}{"\n"}'
    31875

The load balancer shall point at all the compute nodes running SDI workload. The following is an example for HAProxy load balancer:

    # # in the example, the <cluster_name> is "boston" and <base_domain> is "ocp.vslen"
    # cat /etc/haproxy/haproxy.cfg
    ....
    frontend        slcb
        bind        *:9000
        mode        tcp
        option      tcplog
        # # commented blocks are useful for multiple OpenShift clusters or multiple SLC Bridge services
        #tcp-request inspect-delay      5s
        #tcp-request content accept     if { req_ssl_hello_type 1 }

        use_backend  boston-slcb       #if { req_ssl_sni -m end -i boston.ocp.vslen  }
        #use_backend raleigh-slcb      #if { req_ssl_sni -m end -i raleigh.ocp.vslen }

    backend         boston-slcb
        balance     source
        mode        tcp
        server      sdi-worker1        sdi-worker1.boston.ocp.vslen:31875   check
        server      sdi-worker2        sdi-worker2.boston.ocp.vslen:31875   check
        server      sdi-worker3        sdi-worker3.boston.ocp.vslen:31875   check

    backend         raleigh-slcb
    ....

The SLC Bridge can then be accessed at the URL `https://boston.ocp.vslen:9000/docs/index.html` as long as `boston.ocp.vslen` resolves correctly to the load balancer's IP.

### 5.2. SDI Installation Parameters {#sdi-installation-parameters}

Please follow SAP's guidelines on configuring the SDI while paying attention to the following additional comments:

Name                                                                  | Condition                                                                                      | Recommendation
----                                                                  | -------                                                                                        | ---------
Kubernetes Namespace                                                  | Always                                                                                         | Must match the project name chosen in the [Project Setup](#project-setup) (e.g. `sdi`)
Installation Type                                                     | Installation or Update                                                                         | Choose `Advanced Installation` if you need to specify you want to choose particular storage class or there is no [default storage class (4.8)](https://docs.openshift.com/container-platform/4.8/storage/dynamic-provisioning.html#storage-class-annotations_dynamic-provisioning) set or you want to deploy multiple SDI instances on the same cluster.
Container Image Repository                                            | Installation                                                                                   | Must be set to the [container image registry](#prereq-container-image-registry).
Cluster Proxy Settings                                                | Advanced Installation or Update                                                                | Choose *yes* if a local HTTP(S) proxy must be used to access external web resources.
Cluster No Proxy                                                      | When `Cluster Proxy Settings` is configured.                                                   | Please refer to the [HTTP proxy configuration](#apx-http-proxy-configuration).
Backup Configuration                                                  | Installation or Upgrade from a system in which backups are not enabled                         | For a production environment, please choose yes. [**⁴**](#ftnt-validated-s3-endpoints)
Checkpoint Store Configuration                                        | Installation                                                                                   | Recommended for production deployments. If backup is enabled, it is enabled by default.
Checkpoint Store Type                                                 | If *Checkpoint Store Configuration* parameter is enabled.                                      | Set to *S3 compatible object store* if using for example ODF or NetApp StorageGRID as the object storage. See [Using NooBaa as object storage gateway](#configure-s3-with-noobaa) or [NetApp StorageGRID](https://access.redhat.com/articles/5221421)  for more details.
Disable Certificate Validation                                        | If *Checkpoint Store Configuration* parameter is enabled.                                      | Please choose *yes* if using the HTTPS for your object storage endpoint secured with a certificate having a self-signed CA. For ODF NooBaa, you can set it to *no*.
Checkpoint Store Validation                                           | Installation                                                                                   | Please make sure to validate the connection during the installation time. Otherwise in case an incorrect value is supplied, the installation will fail at a later point.
Container Registry Settings for Pipeline Modeler                      | Advanced Installation                                                                          | Shall be changed if the same registry is used for [more than one SAP Data Intelligence instance](#multiple-sdi-instances). Either another `<registry>` or a different `<prefix>` or both will do.
StorageClass Configuration                                            | Advanced Installation                                                                          | Configure this if you want to choose different dynamic storage provisioners for different SDI components or if there's no [default storage class (4.8)](https://docs.openshift.com/container-platform/4.8/storage/dynamic-provisioning.html#defining-storage-classes_dynamic-provisioning) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/dynamic-provisioning.html#defining-storage-classes_dynamic-provisioning) set or you want to choose non-default storage class for the SDI components.
Default StorageClass                                                  | Advanced Installation and if storage classes are configured                                    | Set this if there's no [default storage class (4.8)](https://docs.openshift.com/container-platform/4.8/storage/dynamic-provisioning.html#defining-storage-classes_dynamic-provisioning) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/dynamic-provisioning.html#defining-storage-classes_dynamic-provisioning) set or you want to choose non-default storage class for the SDI components.
Enable Kaniko Usage                                                   | Advanced Installation                                                                          | Must be enabled on OpenShift 4.
Container Image Repository Settings for SAP Data Intelligence Modeler | Advanced Installation or Upgrade                                                               | If using the same registry for multiple SDI instances, choose "yes".
Container Registry for Pipeline Modeler                               | Advanced Installation and if "Use different one" option is selected in the previous selection. | If using the same registry for multiple SDI instances, it is required to use either different prefix (e.g. `local.image.registry:5000/mymodelerprefix2`) or a different registry.
Loading NFS Modules                                                   | Advanced Installation                                                                          | Feel free to say "no". This is no longer of concern as long as [the loading of the needed kernel modules](#preload-kernel-modules-post) has been configured.
Additional Installer Parameters                                       | Advanced Installation                                                                          | Please include `-e vsystem.vRep.exportsMask=true`. If omitted and SDI Observer is running, it will apply this parameter on your behalf.

<span id="ftnt-validated-s3-endpoints" markdown="1">**⁴**</span> Note that the validated S3 API endpoint providers are ODF' NooBaa 4.6.4 or newer, ODF 4.6 in external mode and NetApp StorageGRID

### 5.3. Project setup {#project-setup}

It is assumed the `sdi` project has been already created during [SDI Observer's prerequisites](#sdi-observer-prereq).

Login to OpenShift as a *cluster-admin*, and perform the following configurations for the installation:

    # change to the SDI_NAMESPACE project using: oc project "${SDI_NAMESPACE:-sdi}"
    oc adm policy add-scc-to-group anyuid "system:serviceaccounts:$(oc project -q)"
    oc adm policy add-scc-to-user privileged -z default
    oc adm policy add-scc-to-user privileged -z mlf-deployment-api
    oc adm policy add-scc-to-user privileged -z vora-vflow-server
    oc adm policy add-scc-to-user privileged -z "vora-vsystem-$(oc project -q)"
    oc adm policy add-scc-to-user privileged -z "vora-vsystem-$(oc project -q)-vrep"

For the SDI 3.2 and prior versions:

    oc adm policy add-scc-to-user privileged -z "$(oc project -q)-elasticsearch"
    oc adm policy add-scc-to-user privileged -z "$(oc project -q)-fluentd"

Start from SDI 3.3 version:

    oc adm policy add-scc-to-user privileged -z "diagnostics-elasticsearch"
    oc adm policy add-scc-to-user privileged -z "diagnostics-fluentd"

Red Hat is aware that the changes do not comply with best practices and substantially decrease cluster's security. Therefor it is not recommended to share the Data Intelligence nodes with other workloads. As stated [earlier](#ftnt-security-disclaimer), please consult SAP directly if you wish for an improvement.

### 5.4. Install SDI {#sdi-install-with-slcb}

Please follow the official procedure according to [Install using SLC Bridge in a Kubernetes Cluster with Internet Access (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/7e4847e241c340b3a3c50a5db11b46e2.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/7e4847e241c340b3a3c50a5db11b46e2.html).

### 5.5. SDI Post installation steps {#sdi-post-installation}

#### 5.5.1. *(Optional)* Expose SDI services externally {#expose-services}

There are multiple possibilities how to make SDI services accessible outside of the cluster. Compared to Kubernetes, OpenShift offers additional method, which is recommended for most of the scenarios including SDI System Management service. It's based on [OpenShift Ingress Operator (4.8)](https://docs.openshift.com/container-platform/4.8/networking/ingress-operator.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/networking/ingress-operator.html)

For SAP Vora Transaction Coordinator and SAP HANA Wire, please use [the official suggested method available to your environment (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/221c467fe77e47619630bac6f071c40d.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/221c467fe77e47619630bac6f071c40d.html).

##### 5.5.1.1. Using OpenShift Ingress Operator {#expose-with-routes}

**NOTE** Instead of using this manual approach, it is now recommended to let the SDI Observer to manage the route creation and updates instead. If the SDI Observer has been deployed with `MANAGE_VSYSTEM_ROUTE`, this section can be skipped. To configure it ex post, please execute the following:

    # oc set env -n "${NAMESPACE:-sdi-observer}" dc/sdi-observer MANAGE_VSYSTEM_ROUTE=true
    # # wait for the observer to get re-deployed
    # oc rollout status -n "${NAMESPACE:-sdi-observer}" -w dc/sdi-observer

Or please continue with the manual route creation.

OpenShift allows you to access the Data Intelligence services via [Ingress Controllers (4.8)](https://docs.openshift.com/container-platform/4.8/networking/ingress-operator.html#nw-ingress-controller-configuration-parameters_configuring-ingress) / [(4.6)](https://docs.openshift.com/container-platform/4.6/networking/ingress-operator.html#nw-ingress-controller-configuration-parameters_configuring-ingress) as opposed to the regular [NodePorts (4.8)](https://docs.openshift.com/container-platform/4.8/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-nodeport.html#nw-using-nodeport_configuring-ingress-cluster-traffic-nodeport) / [(4.6)](https://docs.openshift.com/container-platform/4.6/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-nodeport.html#nw-using-nodeport_configuring-ingress-cluster-traffic-nodeport)  For example, instead of accessing the vsystem service via `https://worker-node.example.com:32322`, after the service exposure, you will be able to access it at `https://vsystem-sdi.apps.<cluster_name>.<base_domain>`. This is an alternative to the official guide documentation to [Expose the Service On Premise (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/cdc6e33e338d497e99f594568da986b5.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/cdc6e33e338d497e99f594568da986b5.html).

There are two of kinds routes secured with TLS. The `reencrypt` kind, allows for a custom signed or self-signed certificate to be used. The other kind is `passthrough` which uses the pre-installed certificate generated or passed to the installer.

###### 5.5.1.1.1. Export services with an reencrypt route {#expose-with-reencrypt-route}

With this kind of route, different certificates are used on client and service sides of the route. The router stands in the middle and re-encrypts the communication coming from either side using a certificate corresponding to the opposite side. In this case, the client side is secured by a provided certificate and the service side is encrypted with the original certificate generated or passed to the SAP Data Intelligence installer. This is the same kind of route SDI Observer creates automatically.

The reencrypt route allows for securing the client connection with a proper signed certificate.

1. Look up the `vsystem` service:

        # oc project "${SDI_NAMESPACE:-sdi}"            # switch to the Data Intelligence project
        # oc get services | grep "vsystem "
        vsystem   ClusterIP   172.30.227.186   <none>   8797/TCP   19h

   When exported, the resulting hostname will look like `vsystem-${SDI_NAMESPACE}.apps.<cluster_name>.<base_domain>`. However, an arbitrary hostname can be chosen instead as long as it resolves correctly to the IP of the router.

2. Get, generate or use the default certificates for the route. In this example, the default self-signed certificate used by router is used to secure the connection between the client and OpenShift's router. The CA certificate for clients can be obtained from the `router-ca` secret located in the `openshift-ingress-operator` namespace:

        # oc get secret -n openshift-ingress-operator -o json router-ca | \
            jq -r '.data as $d | $d | keys[] | select(test("\\.crt$")) | $d[.] | @base64d' >router-ca.crt

3. Obtain the SDI's root certificate authority bundle generated at the SDI's installation time. The generated bundle is available in the `ca-bundle.pem` secret in the `sdi` namespace.

        # oc get -n "${SDI_NAMESPACE:-sdi}" -o go-template='{{index .data "ca-bundle.pem"}}' \
            secret/ca-bundle.pem | base64 -d >sdi-service-ca-bundle.pem

4. Create the reencrypt route for the vsystem service like this:

        # oc create route reencrypt -n "${SDI_NAMESPACE:-sdi}" --dry-run -o json \
                --dest-ca-cert=sdi-service-ca-bundle.pem --service vsystem \
                --insecure-policy=Redirect | \
            oc annotate --local -o json -f - haproxy.router.openshift.io/timeout=2m | \
            oc apply -f -
        # oc get route
        NAME      HOST/PORT                                                  SERVICES  PORT      TERMINATION         WILDCARD
        vsystem   vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>  vsystem   vsystem   reencrypt/Redirect  None

5. Verify the connection:

        # # use the HOST/PORT value obtained from the previous command instead
        # curl --cacert router-ca.crt https://vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>/

###### 5.5.1.1.2. Export services with a passthrough route {#expose-with-passthrough-route}

With the `passthrough` route, the communication is encrypted by the SDI service's certificate all the way to the client.

**NOTE**: If possible, please prefer the [`reencrypt` route](#expose-with-reencrypt-route) because the hostname of vsystem certificate cannot be verified by clients as can be seen in the following output:

    # oc get -n "${SDI_NAMESPACE:-sdi}" -o go-template='{{index .data "ca-bundle.pem"}}' \
        secret/ca-bundle.pem | base64 -d >sdi-service-ca-bundle.pem
    # openssl x509 -noout -subject -in sdi-service-ca-bundle.pem
    subject=C = DE, ST = BW, L = Walldorf, O = SAP, OU = Data Hub, CN = SAPDataHub

1. Look up the `vsystem` service:

        # oc project "${SDI_NAMESPACE:-sdi}"            # switch to the Data Intelligence project
        # oc get services | grep "vsystem "
        vsystem   ClusterIP   172.30.227.186   <none>   8797/TCP   19h

2. Create the route:

        # oc create route passthrough --service=vsystem --insecure-policy=Redirect
        # oc get route
        NAME      HOST/PORT                                                  PATH  SERVICES  PORT      TERMINATION           WILDCARD
        vsystem   vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>        vsystem   vsystem   passthrough/Redirect  None

   You can modify the hostname with `--hostname` parameter. Make sure it resolves to the router's IP.

3. Access the System Management service at `https://vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>` to verify.

##### 5.5.1.2. Using NodePorts {#expose-with-nodeports}

**NOTE** For OpenShift, an exposure using [routes](#expose-with-routes) is preferred although only possible for the System Management service (aka `vsystem`).

**Exposing SAP Data Intelligence vsystem**

- Either with an auto-generated node port:

        # oc expose service vsystem --type NodePort --name=vsystem-nodeport --generator=service/v2
        # oc get -o jsonpath='{.spec.ports[0].nodePort}{"\n"}' services vsystem-nodeport
        30617

- Or with a specific node port (e.g. 32123):

        # oc expose service vsystem --type NodePort --name=vsystem-nodeport --generator=service/v2 --dry-run -o yaml | \
            oc patch -p '{"spec":{"ports":[{"port":8797, "nodePort": 32123}]}}' --local -f - -o yaml | oc apply -f -

The original service remains accessible on the same `ClusterIP:Port` as before. Additionally, it is now accessible from outside of the cluster under the node port.

**Exposing SAP Vora Transaction Coordinator and HANA Wire**

    # oc expose service vora-tx-coordinator-ext --type NodePort --name=vora-tx-coordinator-nodeport --generator=service/v2
    # oc get -o jsonpath='tx-coordinator:{"\t"}{.spec.ports[0].nodePort}{"\n"}hana-wire:{"\t"}{.spec.ports[1].nodePort}{"\n"}' \
        services vora-tx-coordinator-nodeport
    tx-coordinator: 32445
    hana-wire:      32192

The output shows the generated node ports for the newly exposed services.

#### 5.5.2. Configure the Connection to Data Lake {#sdi-post-sdl}

Please follow the official post-installation instructions at [Configure the Connection to `DI_DATA_LAKE` (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/a6b555f56d8c4641bd1a248231202050.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/a6b555f56d8c4641bd1a248231202050.html).

In case the ODF is used as a backing object storage provider, please make sure to use the HTTP service endpoint as documented in [Using NooBaa or RADOS Object Gateway S3 endpoint as object storage](#configure-s3-with-noobaa).

Based on the example output in that section, the configuration may look like this:

Parameter           | Value
---------           | -----
Connection Type     | `SDL`
Id                  | `DI_DATA_LAKE`
Object Storage Type | `S3`
Endpoint            | `http://s3.openshift-storage.svc.cluster.local`
Access Key ID       | `cOxfi4hQhGFW54WFqP3R`
Secret Access Key   | `rIlvpcZXnonJvjn6aAhBOT/Yr+F7wdJNeLDBh231`
Root Path           | `sdi-data-lake-f86a7e6e-27fb-4656-98cf-298a572f74f3`

#### 5.5.3. SDI Validation {#sdi-validation}

Validate SDI installation on OpenShift to make sure everything works as expected. Please follow the instructions in [Testing Your Installation (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/1551785f3d7e4d37af7fe99185f7acb6.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/1551785f3d7e4d37af7fe99185f7acb6.html).

##### 5.5.3.1. Log On to SAP Data Intelligence Launchpad {#sdi-validate-launchpad}

In case the `vsystem` service has been exposed using a [route](#expose-with-routes), the URL can be determined like this:

    # oc get route -n "${SDI_NAMESPACE:-sdi}"
    NAME      HOST/PORT                                                  SERVICES  PORT      TERMINATION  WILDCARD
    vsystem   vsystem-<SDI_NAMESPACE>.apps.<cluster_name>.<base_domain>  vsystem   vsystem   reencrypt    None

The `HOST/PORT` value needs to be then prefixed with `https://`, for example:

    https://vsystem-sdi.apps.boston.ocp.vslen

##### 5.5.3.2. Check Your Machine Learning Setup {#sdi-validate-ml}

In order to upload training and test datasets using ML Data Manager, the user needs to be assigned `app.datahub-app-data.fullAcces` (as of 3.2) or `sap.dh.metadata` (up to 3.1) policy. Please make sure to follow [Using SAP Data Intelligence Policy Management (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/b37aec76667d4eefbbee31fbe2756c48.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/b37aec76667d4eefbbee31fbe2756c48.html) to assign the policies to the users that need them.

#### 5.5.4. Configuration of additional tenants {#sdi-configure-additional-tenants}

When a new tenant is created (using e.g. [Manage Clusters instructions (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/f6942055d03a4dc7bf9d3255efb43ff1.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/f6942055d03a4dc7bf9d3255efb43ff1.html)) it is not configured to work with the container image registry. Therefore, the Pipeline Modeler is unusable and will fail to start until configured.

There are a few steps that need to be performed for each new tenant:

- import CA certificate for the registry via SDI Connection Manager if the CA certificate is self-signed
- as long as a different registry for modeler is used, pull secret needs to be imported to the SDI\_NAMESPACE
- create and import credential secret using the SDI System Management and update the modeler secret if the container image registry requires authentication

If the Red Hat Quay is used, please follow the [Configuring additional SDI tenants](#apx-quay-tenant-configuration).

If the SDI Registry is used, please follow the [SDI Observer Registry tenant configuration](#sdi-observer-registry-tenant-configuration). Otherwise, please make sure to execute the official instructions in the following articles according to your registry configuration:

- [Provide Access Credentials for a Password Protected Container Registry (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/a1cbbc0acc834c0cbbe443f2e0d63ab9.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/a1cbbc0acc834c0cbbe443f2e0d63ab9.html) (as long as your registry for the Pipeline Modeler uses TLS with a self-signed CA)
- [Manage Certificates (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) (as long as your registry requires authentication)

## 6. OpenShift Container Platform Upgrade {#ocp-upgrade}

This section is useful as a guide for performing OpenShift upgrades to the latest asynchronous release[**ⁿ**](#apx-resolve-no-upgrade-path) of the same minor version or to the newer minor release supported by the running SDI instance without upgrading SDI itself.

### 6.1. Pre-upgrade procedures {#ocp-up-pre}

1. Make yourself familiar with the [OpenShift's upgrade guide (4.6 ⇒ 4.7)](https://docs.openshift.com/container-platform/4.7/release_notes/ocp-4-7-release-notes.html#ocp-4-7-installation-and-upgrade) / [(4.7 ⇒ 4.8)](https://docs.openshift.com/container-platform/4.8/release_notes/ocp-4-8-release-notes.html#ocp-4-8-installation-and-upgrade).
2. Plan for SDI downtime.
4. Make sure to [re-configure SDI compute nodes](#ocp-post-node-preparation).

#### 6.1.1. Stop SAP Data Intelligence {#ocp-up-stop-sdi}

In order to speed up the cluster upgrade and/or to ensure SDI's consistency, it is possible to stop the SDI before performing the upgrade.

The procedure is outlined in the [official Administration Guide (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/a5346e472cf944458cfba6e6eea58878.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/a5346e472cf944458cfba6e6eea58878.html). In short, the command is:

    # oc -n "${SDI_NAMESPACE}" patch datahub default --type='json' -p '[
        {"op":"replace","path":"/spec/runLevel","value":"Stopped"}]'

### 6.2. Upgrade OpenShift {#ocp-up-upgrade}

The following instructions outline a process of OpenShift upgrade to a minor release 2 versions higher than the current one. If only an upgrade to the latest asynchronous release[**ⁿ**](#apx-resolve-no-upgrade-path) of the same minor version is desired, please skip steps 5 and 6.

1. [Upgrade OpenShift to a higher minor release or the latest asynchronous release (⇒ 4.6)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.6/html-single/updating_clusters/index#understanding-upgrade-channels_updating-cluster-between-minor).
2. If having OpenShift Data Foundation deployed, [update ODF to the latest supported release for the current OpenShift release](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.7/html/updating_openshift_container_storage/index) according to the [interoperability guide](https://access.redhat.com/articles/4731161).
3. Update OpenShift client tools on the *Management host* to match the target [**※**](#ftnt-oc-client-matching-target-release) OpenShift release. On RHEL 8, one can do it like this:

        # current=4.6; new=4.8
        # sudo subscription-manager repos \
            --disable=rhocp-${current}-for-rhel-8-x86_64-rpms --enable=rhocp-${new}-for-rhel-8-x86_64-rpms
        # sudo dnf update -y openshift-clients

4. Update SDI Observer to use the OpenShift client tools matching the target [**※**](#ftnt-oc-client-matching-target-release) OpenShift release by following [Re-Deploying SDI Observer while reusing the previous parameters](#sdi-observer-redeploy).
5. [Upgrade OpenShift to a higher minor release or the latest asynchronous release (⇒ 4.8)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.8/html-single/updating_clusters/index#understanding-upgrade-channels_updating-cluster-between-minor) [**ⁿ**](#apx-resolve-no-upgrade-path).
6. If having OpenShift Data Foundation deployed, [update ODF to the latest supported release for the current OpenShift release](https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.8/html/updating_openshift_container_storage/index) according to the [interoperability guide](https://access.redhat.com/articles/4731161).

<span id="ftnt-oc-client-matching-target-release" markdown="1">**※**</span> for the initial OpenShift release `4.X`, the target release is `4.(X+2)`; if performing just the latest asynchronous release[**ⁿ**](#apx-resolve-no-upgrade-path) upgrade, the target release is `4.X`

### 6.3. Post-upgrade procedures {#ocp-up-post}

1. Start SAP Data Intelligence as outlined in the [official Administration Guide (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/a5346e472cf944458cfba6e6eea58878.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/a5346e472cf944458cfba6e6eea58878.html). In short, the command is:

        # oc -n "${SDI_NAMESPACE}" patch datahub default --type='json' -p '[
            {"op":"replace","path":"/spec/runLevel","value":"Started"}]'

## 7. SAP Data Intelligence Upgrade or Update {#sdh-upgrade}

**NOTE** This section covers an upgrade of SAP Data Intelligence to a newer minor, micro or patch release. Sections related only to the former or the latter will be annotated with the following annotations:

- *(upgrade)* to denote a section specific to an upgrade from Data Intelligence to a newer minor release (`3.X ⇒ 3.(X+1)`)
- *(update)* to denote a section specific to an update of Data Intelligence to a newer micro/patch release (`3.X.Y ⇒ 3.X.(Y+1)`)
- annotation-free are sections relating to both

The following steps must be performed in the given order. Unless an OpenShift upgrade is needed, the steps marked with *(ocp-upgrade)* can be skipped.

### 7.1. Pre-upgrade or pre-update procedures {#up-pre}

1. Make sure to get familiar with the [official SAP Upgrade guide (3.0 ⇒ 3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/b87299d2e8bc436baadfa020abb59892.html) / [(3.1 ⇒ 3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/b87299d2e8bc436baadfa020abb59892.html).
2. *(ocp-upgrade)* Make yourself familiar with the [OpenShift's upgrade guide (4.6 ⇒ 4.7)](https://docs.openshift.com/container-platform/4.7/release_notes/ocp-4-7-release-notes.html#ocp-4-7-installation-and-upgrade) / [(4.7 ⇒ 4.8)](https://docs.openshift.com/container-platform/4.8/release_notes/ocp-4-8-release-notes.html#ocp-4-8-installation-and-upgrade).
3. Plan for a downtime.
4. Make sure to [re-configure SDI compute nodes](#ocp-post-node-preparation).
5. 

#### 7.1.1. Execute SDI's Pre-Upgrade Procedures {#up-sdi-pre}

Please follow [the official Pre-Upgrade procedures (3.0 ⇒ 3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/18a698c0458d406e962276700ea82f02.html) / [(3.1 ⇒ 3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/18a698c0458d406e962276700ea82f02.html).

##### 7.1.1.1. Automated route removal {#up-sdi-pre-rmroute-automated}

SDI Observer now allows to manage creation and updates of vsystem route for external access. It takes care of updating route's destination certificate during SDI's update. It can also be instructed to keep the route deleted which is useful during SDI updates. You can instruct the SDI Observer to delete the route like this:

1. ensure SDI Observer is managing the route already:

        # oc set env -n "${NAMESPACE:-sdi-observer}" --list dc/sdi-observer | grep MANAGE_VSYSTEM_ROUTE
        MANAGE_VSYSTEM_ROUTE=true

   if there is no output or `MANAGE_VSYSTEM_ROUTE` is not one of `true`, `yes` or `1`, please follow the [Manual route removal](#up-sdi-pre-rmroute-manual) instead.

2. instruct the observer to keep the route removed:

        # oc set env -n "${NAMESPACE:-sdi-observer}" dc/sdi-observer MANAGE_VSYSTEM_ROUTE=removed
        # # wait for the observer to get re-deployed
        # oc rollout status -n "${NAMESPACE:-sdi-observer}" -w dc/sdi-observer

##### 7.1.1.2.  Manual route removal {#up-sdi-pre-rmroute-manual}

If you exposed the vsystem service using routes, delete the route:

    # # note the hostname in the output of the following command
    # oc get route -n "${SDI_NAMESPACE:-sdi}"
    # # delete the route
    # oc delete route -n "${SDI_NAMESPACE:-sdi}" --all

#### 7.1.2. *(upgrade)* Prepare SDI Project {#up-prepare-project}

Grant the needed security context constraints to the new service accounts by executing the commands from the [project setup](#project-setup). **NOTE**: Re-running the commands that have been run already, will do no harm.

### 7.2. Update or Upgrade SDI {#up-sdi-do}

#### 7.2.1. Update Software Lifecycle Container Bridge {#up-slcb}

Before updating the SLC Bridge, please consider [exposing it via Ingress Controller](#sdi-slcb-ingress).

If you decide to continue using the NodePort service load-balanced by an external load balancer, make sure to note down the current service node port:

    # oc get -o jsonpath='{.spec.ports[0].nodePort}{"\n"}' -n sap-slcbridge \
        svc/slcbridgebase-service
    31555

Please follow the [official documentation (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/0986e8da1d8f43379be9c7999f9ff280.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/0986e8da1d8f43379be9c7999f9ff280.html) to obtain the binary and updating its resources on OpenShift cluster.

If exposed via Ingress Controller, you can skip the next step. Otherwise, re-set the nodePort to the previous value so no changes on load-balancer side are necessary.

        # nodePort=31555    # change your value to the desired one
        # oc patch --type=json -n sap-slcbridge svc/slcbridgebase-service -p '[{
            "op":"add", "path":"/spec/ports/0/nodePort","value":'"$nodePort"'}]'

#### 7.2.2. *(upgrade)* Upgrade SAP Data Intelligence to a newer minor release {#up-sdi-minor}

Execute the SDI upgrade according to [the official instructions (DH 3.0 ⇒ 3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/31079833a65f4f379d5a76957ff8073c.html) / [(DH 3.1 ⇒ 3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/31079833a65f4f379d5a76957ff8073c.html).

### 7.3. *(ocp-upgrade)* Upgrade OpenShift {#up-ocp-post-sdi}

Depending on the target SDI release, OpenShift cluster must be upgraded either to a newer minor release or to the latest asynchronous release[**ⁿ**](#apx-resolve-no-upgrade-path) for the current minor release.

Upgraded/Current SDI release | Desired and validated OpenShift Releases
---------------------------- | ---------------------------------
3.2                          | 4.8
3.1                          | 4.6
3.0                          | 4.6

If the current OpenShift release is two or more releases behind the desired, OpenShift cluster must be upgraded iteratively to each successive minor release until the desired one is reached.

1. *(optional)* [Stop the SAP Data Intelligence](#ocp-up-stop-sdi) as it will speed up the cluster update and ensure SDI's consistency.
2. Make sure to follow the official upgrade instructions for your upgrade path:

    - 4.6 [⇒ 4.7](https://docs.openshift.com/container-platform/4.7/release_notes/ocp-4-7-release-notes.html#ocp-4-7-installation-and-upgrade) [⇒ 4.8](https://docs.openshift.com/container-platform/4.8/release_notes/ocp-4-8-release-notes.html#ocp-4-8-installation-and-upgrade)

3. When on OpenShift 4.7, please follow the [Re-deploying SDI Observer](#sdi-observer-redeploy) to update the observer. Please make sure to set `MANAGE_VSYSTEM_ROUTE` to `remove` until the SDI's update is finished. Please set the desired OpenShift minor release (e.g. `OCP_MINOR_RELEASE=4.8`).

3. *(optional)* [Start the SAP Data Intelligence](#ocp-up-post) again if the desired OpenShift release has been reached.
4. Upgrade OpenShift client tools on the *Management host*. The example below can be used on RHEL 8:

        # current=4.6; new=4.8
        # sudo subscription-manager repos \
            --disable=rhocp-${current}-for-rhel-8-x86_64-rpms --enable=rhocp-${new}-for-rhel-8-x86_64-rpms
        # sudo dnf update -y openshift-clients

### 7.4. SAP Data Intelligence Post-Upgrade Procedures {#up-sdi-post}

1. Execute the [Post-Upgrade Procedures for the SDH (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/5b4ad21b77aa4b7585c7a9965b15da81.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/5b4ad21b77aa4b7585c7a9965b15da81.html).

2. Re-create the route for the vsystem service using one of the following methods:

    - *(recommented)* instruct SDI Observer to manage the route:

            # oc set env -n "${NAMESPACE:-sdi-observer}" dc/sdi-observer MANAGE_VSYSTEM_ROUTE=true
            # # wait for the observer to get re-deployed
            # oc rollout status -n "${NAMESPACE:-sdi-observer}" -w dc/sdi-observer

    - follow [Expose SDI services externally](#expose-services) to recreate the route manually from scratch

### 7.5. Validate SAP Data Intelligence {#up-validate}

Validate SDI installation on OpenShift to make sure everything works as expected. Please follow the instructions in [Testing Your Installation (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/fb20df42d2f94c62ad36ae6368c1fae3.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/fb20df42d2f94c62ad36ae6368c1fae3.html).

## 8. Appendix {#appendix}

### 8.1. SDI uninstallation {#uninstallation}

Please follow the SAP documentation [Uninstalling SAP Data Intelligence using the SLC Bridge (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/1f56ade6c15b48e6a8e6d5361d325267.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/1f56ade6c15b48e6a8e6d5361d325267.html).

Additionally, make sure to delete the `sdi` project as well, e.g.:

    # oc delete project sdi

**NOTE**: With this, SDI Observer loses permissions to view and modify resources in the deleted namespace. If a new SDI installation shall take place, SDI observer needs to be re-deployed.

Optionally, one can also delete SDI Observer's namespace, e.g.:

    # oc delete project sdi-observer

**NOTE**: this will also delete the SDI registry if deployed using SDI Observer which means the mirroring needs to be performed again during a new installation. If SDI Observer (including the registry and its data) shall be preserved for the next installation, please make sure to [re-deploy it](#sdi-observer-redeploy) once the `sdi` project is re-created.

When done, you may continue with a [new installation round](#sdi-install) in the same or another namespace.

### 8.2. Quay Registry for SDI {#apx-quay-for-sdi}

Red Hat Quay Registry has been validated to host SAP Data Intelligence images. The Quay registry can run directly on the OpenShift cluster together with SDI, on another OpenShift cluster or standalone.

**Note:** Red Hat Quay 3.6 or newer is compatible with SDI images.

Once Red Hat Quay is [deployed according to the documentation](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6), make sure to [configure OpenShift cluster to trust the registry](#ocp-configure-ca-trust).

#### 8.2.1. Quay namespaces, users and accounts preparations {#apx-quay-namespaces}

1. [Create a new organization](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#org-create). In this example, we will call the organization `sdi`.

    - This organization will host all the images needed by SLC Bridge, SAP DI and SAP DI operator.

2. As the Quay Superadmin [create a new user](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#user-create) (e.g. `sdi_slcb`). Please note the credentials. The user will be used as a robot account by SLC Bridge and OpenShift (not by a human). So far, the regular Quay robot account cannot be used because the robot accounts cannot create repositories on push.
3. Grant the `sdi_slcb` user at least the `Creator` access to the `sdi` organization.

    - Either by adding the user to the `owners` team in "Teams and Membership" pane.
    - Or by [creating a new team](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#allow-team-access-org-repo) in the `sdi` organization called e.g. `pushers` with the `Creator` [team role assigned](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#set-team-role) and [adding the `sdi_slcb` user as a member](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#add-users-to-team).

4. (*optional*) As the Superadmin, [create another user](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#add-users-to-team) for pipeline modeler (e.g. `sdi_default_modeler` where `default` stands for the default tenant).

    - Advantages of having a separate registry namespace and users for each tenant's pipeline modeler:
        - Images can be easily pruned on per-tenant basis. Once the SDI tenant is no longer needed, the corresponding Quay user can be deleted and its images will be automatically pruned from the registry and space recovered.
        - Improved security. SDI tenant users cannot access images of other SDI tenants.
    - This user will be used again as a robot account, similar to `sdi_slcb`.
    - For user's E-mail address, any fake address will do as long as it is unique among all Quay users.
    - The name of the user is at the same time the namespace where the images will be pushed to and pull from.
    - Make sure to note the credentials.
    - The user must be able to pull from the `sdi` organization.

   In order for the user to pull from `sdi` organization, make sure to perform also the following.

    1. As the owner of the `sdi` organization, go to its "Teams and Membership" pane, [create a new team](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#allow-team-access-org-repo) (e.g. `pullers`) with the `Member` [Team Role](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#set-team-role).
    2. Click on "Set permissions for pullers" and make sure the team can Read all the repositories that already exist in the `sdi` organization.
    3. Click on the `puller` team, search for `sdi_default_modeler` user and [add him to the team](https://access.redhat.com/documentation/en-us/red_hat_quay/3.6/html-single/use_red_hat_quay/index#add-users-to-team).
    4. Go back to `Default Permissions` of the `sdi` organization, click on "Create Default Permission" and add the "Read" permission to the `puller` team for repositories created by `Anyone`.

5. (*optional*) Repeat the previous step for any additional SDI tenant you are going to create.

#### 8.2.2. Determine the Image Repository {#apx-quay-determine-pull-spec}

The Image Repository [Input Parameter](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/abfa9c73f7704de2907ea7ff65e7a20a.html) is composed of `<hostname>/<namespace>`.

- The registry `<hostname>` for Quay running on the OpenShift cluster can be determined on the *Management host* like this:

        # oc get route --all-namespaces -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' \
                -l quay-component=quay-app-route

  An example output:

        quay.apps.cluster.example.com

  In case your local Quay registry runs outside of OpenShift cluster, you will need to determine its hostname by other means.

- The `<namespace>` is either the organization name or username. For `sdi` organization, the `<namespace>` is `sdi`.

In this example, the resulting Image Repository parameter will be `quay.apps.cluster.example.com/sdi`.

#### 8.2.3. Importing Quay's CA Certificate to OpenShift {#apx-quay-ocp-ca-import}

If you haven't done it already, please make sure to make OpenShift cluster trust the Quay registry.

1. If the Quay registry is running on the OpenShift cluster, obtain the `router-ca.crt` of the secret as documented in the [SDI Registry Verification section](#apx-deploy-sdi-registry-verification). Otherwise, please fetch the self-signed CA certificate of your external Quay registry.
2. Follow section [Configure OpenShift to trust container image registry](#ocp-configure-ca-trust) to make the registry trusted.

#### 8.2.4. Configuring additional SDI tenants {#apx-quay-tenant-configuration}

There are three steps that need to be performed for each new SDI tenant:

- import CA certificate for the registry via SDI Connection Manager if the CA certificate is self-signed
- create a and import a vflow pull secret to OpenShift namespace
- create and import credential secret using the SDI System Management and update the modeler secret

In this example, we will operate with a newly created tenant `blue` and we assume that new Quay registry user called `blue_modeler` has been created.

##### 8.2.4.1. Importing Quay's CA Certificate to SAP DI {#apx-quay-ca-import}

1. Please follow step one from [Importing Quay's CA Certificate to OpenShift](#apx-quay-ocp-ca-import) to get the CA certificate localy as `router-ca.crt`.
2. Follow the [Manage Certificates guide (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) to import the `router-ca.crt` via the SDI Connection Management.

##### 8.2.4.2. Create and import vflow pull secret into OpenShift {#apx-quay-import-pull-secret-ocp}

This is needed only if a different Quay namespace is used for each tenant.

1. Login into to your Quay registry as the user `blue_modeler`.
2. Click on your user avatar in the upper right corner, go to "Account Settings" -> "User Settings" and there click on "Create Application Token". Let's use `blue_modeler_quay_token` as the token name.
3. Once the application token is generated, click on it and download the corresponding "Kubernetes Secret". In this example, the downloaded file is called `blue-modeler-quay-token-secret.yaml`.
4. On your *Management host*, import the secret into the `SDI_NAMESPACE` on your OpenShift cluster, e.g.:

        # oc apply -n "${SDI_NAMESPACE:-sdi}" -f blue-modeler-quay-token-secret.yaml

5. In SDI "System Management" of the `blue` tenant, go to the Applications tab, search for `pull`, click on the Edit button and set "Modeler: Docker image pull secret for Modeler" to the name of the imported secret (e.g. `blue-modeler-quay-token-pull-secret`).

##### 8.2.4.3. Import credentials secret to SDI tenant {#apx-quay-import-secret-sdi}

If you have imported the vflow pull secret into OpenShift cluster, you can turn the imported secret into the proper file format for SDI like this:

    # secret=blue-modeler-quay-token-pull-secret
    # oc get -o json -n "${SDI_NAMESPACE:-sdi}" "secret/$secret" | \
        jq -r '.data[".dockerconfigjson"] | @base64d' | jq -r '.auths as $auths | $auths | keys |
            map(. as $address | $auths[.].auth | @base64d | capture("^(?<username>[^:]+):(?<password>.+)$") |
            {"address": $address, "username": .username, "password": .password})' | \
        json2yaml | tee vsystem-registry-secret.txt

Otherwise, create the secret manually like this:

    # cat >/tmp/vsystem-registry-secret.txt <<EOF
    - username: "blue_modeler"
      password: "CHANGEME"
      address: "quay.apps.cluster.example.com"
    EOF

**Note** that the address must not contain any `/<namespace>` suffix!

Import the secret using the SDI System Management by following the official [Provide Access Credentials for a Password Protected Container Registry (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/a1cbbc0acc834c0cbbe443f2e0d63ab9.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/a1cbbc0acc834c0cbbe443f2e0d63ab9.html).

### 8.3. Deploying SDI Registry manually {#apx-deploy-sdi-registry}

The secure container image registry suitable for hosting SAP Data Intelligence images on OpenShift cluster.

#### 8.3.1. Deployment {#apx-deploy-sdi-registry-deployment}

SDI Registry's kubernetes resources are defined in OpenShift Templates. To choose the right template and provide the right parameters for it, it is recommended to use the deployment script documented below.

##### 8.3.1.1. Prerequisites {#apx-deploy-sdi-registry-prerequisites}

1.  OpenShift cluster must be healthy including all the cluster operators.
2.  `jq >= 1.6` binary available on the management host

##### 8.3.1.2. Template instantiation {#apx-deploy-sdi-registry-tmpl-run}

1.  Make the git repository available on your management host.

        # git clone https://github.com/redhat-sap/sap-data-intelligence

2.  Inspect the available arguments of the deployment script:

        # ./sap-data-intelligence/registry/deploy-registry.sh --help

3.  Choose the right set of arguments and make a dry run to see what will happen. The `ubi-prebuilt` flavour will be chosen by default. The image will be pulled from [quay.io/redhat-sap-cop/container-image-registry](https://quay.io/repository/redhat-sap-cop/container-image-registry).

        # ./sap-data-intelligence/registry/deploy-registry.sh --dry-run

4.  Next time, deploy the SDI registry for real and wait until it gets deployed:

        # ./sap-data-intelligence/registry/deploy-registry.sh --wait

##### 8.3.1.3. Generic instantiation for a disconnected environment {#apx-deploy-sdi-registry-disconnected}

There must be another container image registry running outside of the OpenShift cluster to host the image of SDI Registry. That registry should be used to host SAP Data Intelligence images also as long as it is compatible. Otherwise, please follow this guide.

1.  Mirror the pre-built image of SDI Registry to the local registry. For example, on RHEL8:

    -   Where the management host has access to the internet:

            # podman login local.image.registry:5000    # if the local registry requires authentication
            # skopeo copy \
                docker://quay.io/redhat-sap-cop/container-image-registry:latest \
                docker://local.image.registry:5000/container-image-registry:latest

    -   Where the management host *lacks* access to the internet.

        i.  Copy the image on a USB flash on a host having the connection to the internet:

                # skopeo copy \
                    docker://quay.io/redhat-sap-cop/contaimer-image-registry:latest \
                    oci-archive:/var/run/user/1000/usb-disk/container-image-registry:latest

        ii. Plug the USB drive to the management host and mirror the image from it to your `local.image.registry:5000`:

                # skopeo copy \
                    oci-archive:/var/run/user/1000/usb-disk/container-image-registry:latest \
                    docker://local.image.registry:5000/container-image-registry:latest

2.  Make the git repository available on your management host.

        # git clone https://github.com/redhat-sap/sap-data-intelligence

3.  Inspect the available arguments of the deployment script:

        # ./sap-data-intelligence/registry/deploy-registry.sh --help

4.  Choose the right set of arguments and make a dry run to see what will happen:

        # ./sap-data-intelligence/registry/deploy-registry.sh \
            --image-pull-spec=local.image.registry:5000/container-image-registry:latest --dry-run

5.  Next time, deploy the SDI Registry for real and wait until it gets deployed:

        # ./sap-data-intelligence/registry/deploy-registry.sh \
            --image-pull-spec=local.image.registry:5000/container-image-registry:latest --wait

6.  Please make sure to backup the arguments used for future updates.

#### 8.3.2. Update instructions {#apx-deploy-sdi-registry-update}

So far, updates need to be performed manually.

Please follow the steps outlined in [Template Instantiation](#apx-deploy-sdi-registry-tmpl-run) anew. A re-run of the deployment script will change only what needs to be changed.


#### 8.3.3. Determine Registry's credentials {#apx-deploy-sdi-registry-get-credentials}

The username and password are separated by a colon in the `SDI_REGISTRY_HTPASSWD_SECRET_NAME` secret:

    # # make sure to change the "sdi-registry" to your SDI Registry's namespace
    # oc get -o json -n "sdi-registry" secret/container-image-registry-htpasswd | \
        jq -r '.data[".htpasswd.raw"] | @base64d'
    user-qpx7sxeei:OnidDrL3acBHkkm80uFzj697JGWifvma

#### 8.3.4. Verification {#apx-deploy-sdi-registry-verification}

1.  Obtain Ingress' default self-signed CA certificate:

        # oc get secret -n openshift-ingress-operator -o json router-ca | \
            jq -r '.data as $d | $d | keys[] | select(test("\\.crt$")) | $d[.] | @base64d' >router-ca.crt

2.  Set the `nm` variable to the Kubernetes namespace where SDI Registry runs:

        # nm=sdi-registry

3.  Do a simple test using curl:

        # # determine registry's hostname from its route
        # hostname="$(oc get route -n "$nm" container-image-registry -o jsonpath='{.spec.host}')"
        # curl -I --user user-qpx7sxeei:OnidDrL3acBHkkm80uFzj697JGWifvma --cacert router-ca.crt \
            "https://$hostname/v2/"
        HTTP/1.1 200 OK
        Content-Length: 2
        Content-Type: application/json; charset=utf-8
        Docker-Distribution-Api-Version: registry/2.0
        Date: Sun, 24 May 2020 17:54:31 GMT
        Set-Cookie: d22d6ce08115a899cf6eca6fd53d84b4=9176ba9ff2dfd7f6d3191e6b3c643317; path=/; HttpOnly; Secure
        Cache-control: private

4.  Optionally, make the certificate trusted on your management host (this example is for RHEL7 or newer):

        # sudo cp -v router-ca.crt /etc/pki/ca-trust/source/anchors/router-ca.crt
        # sudo update-ca-trust

5.  Using the podman:

        # # determine registry's hostname from its route
        # hostname="$(oc get route -n "$nm" container-image-registry -o jsonpath='{.spec.host}')"
        # sudo mkdir -p "/etc/containers/certs.d/$hostname"
        # sudo cp router-ca.crt "/etc/containers/certs.d/$hostname/"
        # podman login -u user-qpx7sxeei "$hostname"
        Password:
        Login Succeeded!

#### 8.3.5. Post configuration {#apx-deploy-sdi-registry-post}

By default, the SDI Registry is secured by the Ingress Controller's certificate signed by a self-signed CA certificate. Self-signed certificates are trusted neither by OpenShift nor by SDI.

If the registry is signed by a proper trusted (not self-signed) certificate, this may be skipped.

##### 8.3.5.1. Making SDI Registry trusted by OpenShift {#apx-deploy-sdi-registry-making-sdi-registry-trusted-ocp}

To make the registry trusted by the OpenShift cluster, please follow [Configure OpenShift to trust container image registry](#ocp-configure-ca-trust). You can determine the registry hostname in bash like this:

    # nm="sdi-registry"   # namespace where registry runs
    # registry="$(oc get route -n "$nm" \
        container-image-registry -o jsonpath='{.spec.host}')"; echo "$registry"

##### 8.3.5.2. SDI Observer Registry tenant configuration {#sdi-observer-registry-tenant-configuration}

The default tenant is configured automatically as long as one of the following holds true:

- [SDI Observer](#sdi-observer) is running and configured with `INJECT_CABUNDLE=true` and the right CA certicate is configured with one of `CABUNDLE_*` environment variables (the default values are usually alright).
- [Setting Up Certificates](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/39e8e391d5984e919725e601f089db74.html) has been followed.

**NOTE**: Only applicable once the [SDI installation](#sdi-install) is complete.

Each newly created tenant needs to be configured to be able to talk to the SDI Registry. The initial tenant (the `default`) does not need to be configured manually as it is configured during the installation.

There are two steps that need to be performed for each new tenant:

- import CA certificate for the registry via SDI Connection Manager if the CA certificate is self-signed
- create and import credential secret using the SDI System Management and update the modeler secret

**Import the CA certificate**

1. Obtain the `router-ca.crt` of the secret as documented in the [previous section](#apx-deploy-sdi-registry-verification).
2. Follow the [Manage Certificates guide (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) to import the `router-ca.crt` via the SDI Connection Management.

**Import the credentials secret**

[Determine the credentials](#apx-deploy-sdi-registry-get-credentials) and import them using the SDI System Management by following the official [Provide Access Credentials for a Password Protected Container Registry (3.2)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.2.latest/en-US/a1cbbc0acc834c0cbbe443f2e0d63ab9.html) / [(3.1)](https://help.sap.com/viewer/a8d90a56d61a49718ebcb5f65014bbe7/3.1.latest/en-US/a1cbbc0acc834c0cbbe443f2e0d63ab9.html).

As an alternative to the step "1. Create a secret file that contains the container registry credentials and …", you can also use the following way to create the `vsystem-registry-secret.txt` file:

    # # determine registry's hostname from its route
    # hostname="$(oc get route -n "${NAMESPACE:-sdi-observer}" container-image-registry -o jsonpath='{.spec.host}')"
    # oc get -o json -n "${NAMESPACE:-sdi-observer}" secret/container-image-registry-htpasswd | \
        jq -r '.data[".htpasswd.raw"] | @base64d | sub("^\\s*Credentials:\\s+"; "") | gsub("\\s+"; "") | split(":") |
            [{"username":.[0], "password":.[1], "address":"'"$hostname"'"}]' | \
        json2yaml | tee vsystem-registry-secret.txt

**NOTE**: that `json2yaml` binary from the [remarshal project](https://github.com/dbohdan/remarshal) [must be installed](#apx-install-remarshal) on the *Management host* in addition to `jq`

### 8.4. Configure OpenShift to trust container image registry {#ocp-configure-ca-trust}

If the registry's certificate is signed by a self-signed certificate authority, one must make OpenShift aware of it.

If the registry runs on the OpenShift cluster itself and is exposed via a `reencrypt` or `edge` route with the default TLS settings (no custom TLS certificates set), the CA certificate used is available in the secret `router-ca` in `openshift-ingress-operator` namespace.

To make the registry available via such route trusted, set the route's hostname into the `registry` variable and execute the following code in bash:

    # registry="local.image.registry:5000"
    # caBundle="$(oc get -n openshift-ingress-operator -o json secret/router-ca | \
        jq -r '.data as $d | $d | keys[] | select(test("\\.(?:crt|pem)$")) | $d[.] | @base64d')"
    # # determine the name of the CA configmap if it exists already
    # cmName="$(oc get images.config.openshift.io/cluster -o json | \
        jq -r '.spec.additionalTrustedCA.name // "trusted-registry-cabundles"')"
    # if oc get -n openshift-config "cm/$cmName" 2>/dev/null; then
        # configmap already exists -> just update it
        oc get -o json -n openshift-config "cm/$cmName" | \
            jq '.data["'"${registry//:/..}"'"] |= "'"$caBundle"'"' | \
            oc replace -f - --force
      else
          # creating the configmap for the first time
          oc create configmap -n openshift-config "$cmName" \
              --from-literal="${registry//:/..}=$caBundle"
          oc patch images.config.openshift.io cluster --type=merge \
              -p '{"spec":{"additionalTrustedCA":{"name":"'"$cmName"'"}}}'
      fi

If using a registry running outside of OpenShift or not secured by the default ingress CA certificate, take a look at the official guideline at [Configuring a ConfigMap for the Image Registry Operator (4.8)](https://docs.openshift.com/container-platform/4.8/registry/configuring-registry-operator.html#images-configuration-cas_configuring-registry-operator) / [(4.6)](https://docs.openshift.com/container-platform/4.6/registry/configuring-registry-operator.html#images-configuration-cas_configuring-registry-operator)

To verify that the CA certificate has been deployed, execute the following and check whether the supplied registry name appears among the file names in the output:

    # oc rsh -n openshift-image-registry "$(oc get pods -n openshift-image-registry -l docker-registry=default | \
            awk '/Running/ {print $1; exit}')" ls -1 /etc/pki/ca-trust/source/anchors
    container-image-registry-sdi-observer.apps.boston.ocp.vslen
    image-registry.openshift-image-registry.svc..5000
    image-registry.openshift-image-registry.svc.cluster.local..5000

If this is not feasible, one can also [mark the registry as insecure](#ocp-configure-insecure-registry).

### 8.5. Configure insecure registry {#ocp-configure-insecure-registry}

As a less secure an alternative to the [Configure OpenShift to trust container image registry](#ocp-configure-ca-trust), registry may also be marked as insecure which poses a potential security risk. Please follow [Configuring image settings (4.8)](https://docs.openshift.com/container-platform/4.8/openshift_images/image-configuration.html#images-configuration-file_image-configuration) / [(4.6)](https://docs.openshift.com/container-platform/4.6/openshift_images/image-configuration.html#images-configuration-file_image-configuration) and add the registry to the `.spec.registrySources.insecureRegistries` array. For example:

    apiVersion: config.openshift.io/v1
    kind: Image
    metadata:
      annotations:
        release.openshift.io/create-only: "true"
      name: cluster
    spec:
      registrySources:
        insecureRegistries:
        - local.image.registry:5000

**NOTE**: it may take a couple of tens of minutes until the nodes are reconfigured. You can use the following commands to monitor the progress:

- `watch oc get machineconfigpool`
- `watch oc get nodes`

### 8.6. Running multiple SDI instances on a single OpenShift cluster {#multiple-sdi-instances}

Two instances of SAP Data Intelligence running in parallel on a single OpenShift cluster have been validated. Running more instances is possible, but most probably needs an extra support statement from SAP.

Please consider the following before deploying more than one SDI instance to a cluster:

- Each SAP Data Intelligence instance must run in its own namespace/project.
- Each SAP Data Intelligence instance must use a different prefix or container image registry for the Pipeline Modeler. For example, the first instance can configure "Container Registry Settings for Pipeline Modeler" as `local.image.registry:5000/sdi30blue` and the second as `local.image.registry:5000/sdi30green`.
- It is recommended to [dedicate particular nodes](#ocp-post-node-preparation) to each SDI instance.
- It is recommended to use [network policy (4.8)](https://docs.openshift.com/container-platform/4.8/networking/openshift_sdn/about-openshift-sdn.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/networking/openshift_sdn/about-openshift-sdn.html) SDN mode for completely granular network isolation configuration and improved security. Check [network policy configuration (4.8)](https://docs.openshift.com/container-platform/4.8/networking/network_policy/about-network-policy.html) / [(4.6)](https://docs.openshift.com/container-platform/4.6/networking/network_policy/about-network-policy.html) for further references and examples. This, however, cannot be changed post [OpenShift installation](#ocp-installation).
- If running the production and test (aka blue-green) SDI deployments on a single OpenShift cluster, mind also the following:
    - There is no way to test an upgrade of OpenShift cluster before an SDI upgrade.
    - The idle (non-productive) landscape should have the same network security as the live (productive) one.

To deploy a new SDI instance to OpenShift cluster, please repeat the steps from [project setup](#project-setup) starting from point 6 with a new project name and continue with [SDI Installation](#sdi-install).

### 8.7. Installing remarshal utilities on RHEL {#apx-install-remarshal}

For a few example snippets throughout this guide, either `yaml2json` or `json2yaml` scripts are necessary.

They are provided by the [remarshal project](https://github.com/dbohdan/remarshal) and shall be installed on the *Management host* in addition to `jq`. On RHEL 8.2, one can install it this way:

    # sudo dnf install -y python3-pip
    # sudo pip3 install remarshal

### 8.8. (footnote **ⁿ**) Upgrading to the next minor release from the latest asynchronous release {#apx-resolve-no-upgrade-path}

If the OpenShift cluster is subscribed to [the stable channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#stable-version-channel_understanding-upgrade-channels-releases), its latest available micro release for the current minor release may not be upgradable to a newer minor release.

Consider the following example:

- The OpenShift cluster is of release `4.5.24`.
- The latest asynchronous release available in stable-4.5 channel is `4.5.30`.
- The latest stable 4.6 release is `4.6.15` (available in `stable-4.6` channel).
- From the `4.5.24` micro release, one can upgrade to one of `4.5.27`, `4.5.28`, `4.5.30`, `4.6.13` or `4.6.15`
- However, from the `4.5.30` one cannot upgrade to any newer release because no upgrade path has been validated/provided yet in the stable channel.

Therefor, OpenShift cluster can get stuck on 4.5 release if it is first upgraded to the latest asynchronous release `4.5.30` instead of being upgraded directly to one of the `4.6` minor releases. However, at the same time, the [fast-4.6 channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#fast-version-channel_understanding-upgrade-channels-releases) contains `4.6.16` release with an upgrade path from `4.5.30`. The `4.6.16` release appears in the `stable-4.6` channel sooner of later after being introduced in the [fast channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#fast-version-channel_understanding-upgrade-channels-releases) first.

To amend the situation without waiting for an upgrade path to appear in the [stable channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#stable-version-channel_understanding-upgrade-channels-releases):

1. Temporarily [switch](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#switching-between-channels_understanding-upgrade-channels-releases) to the [fast-4.X channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#fast-version-channel_understanding-upgrade-channels-releases).
2. Perform the upgrade.
3. Switch back to the [stable-4.X channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#stable-version-channel_understanding-upgrade-channels-releases).
4. Continue performing upgrades to the latest micro release available in the [stable-4.X channel](https://docs.openshift.com/container-platform/4.6/updating/understanding-upgrade-channels-release.html#stable-version-channel_understanding-upgrade-channels-releases).

### 8.9. HTTP Proxy Configuration {#apx-http-proxy-configuration}

HTTP(S) Proxy must be configured on different places. The corresponding No Proxy settings are treated differently by different components.

- *management host*
- OpenShift cluster
- SLC Bridge
- SAP Data Intelligence

The sections below assume the following:
- cluster's base domain is `example.com`
- cluster name is `foo`, which means its API is listening at `api.foo.example.com:6443`
- the local proxy server is listening at `http://proxy.example.com:3128`
- *management host*'s hostname is jump.example.com, we should add its shortname (`jump`) to the `NO_PROXY`
- the local network CIDR is `192.168.128.0/24`
- the OpenShift's service network has the default range of `172.30.0.0/16`

#### 8.9.1. Configuring HTTP Proxy on the management host {#apx-http-proxy-management-host}

Please export the Proxy environment variables on your *management host* according to your Linux distribution. For RHEL, please follow [How to apply a system wide proxy](https://access.redhat.com/articles/2133021). For example in BASH:

    # sudo cp /dev/stdin /etc/profile.d/http_proxy.sh <<EOF
    export http_proxy=http://proxy.example.com:3128
    export https_proxy=http://proxy.example.com:3128
    export no_proxy=localhost,127.0.0.1,jump,.example.com,192.168.128.0/24
    EOF
    # source /etc/profile.d/http_proxy.sh

Where the `.example.com` is a wildcard pattern matching any subdomains like `foo.example.com`.

#### 8.9.2. Configuring HTTP Proxy on the OpenShift cluster {#apx-http-proxy-ocp}

Usually, the OpenShift is configured to use the proxy [during its installation](https://docs.openshift.com/container-platform/4.8/installing/installing_bare_metal/installing-restricted-networks-bare-metal.html#installation-configure-proxy_installing-restricted-networks-bare-metal).

But it is also possible to [set/re-configure it ex-post](https://docs.openshift.com/container-platform/4.8/networking/enable-cluster-wide-proxy.html).

An example configuration could look like this:

    # oc get proxy/cluster -o json | jq '.spec'
    {
      "httpProxy": "http://proxy.example.com:3128",
      "httpsProxy": "http://proxy.example.com:3128",
      "noProxy": "192.168.128.0/24,jump,.local,.example.com",
      "trustedCA": {
        "name": "user-ca-bundle"
      }
    }

Please keep in mind that wildcard characters (e.g. `*.example.com`) are not supported by OpenShift.

The complete `no_proxy` list extended for container and service networks and additional service names is generated automatically and is stored in the `.status.noProxy` field of the proxy object:

    # oc get proxy/cluster -o json | jq -r '.status.noProxy'
    .cluster.local,.local,.example.com,.svc,10.128.0.0/14,127.0.0.1,172.30.0.0/16,192.168.128.0/24,api-int.foo.example.com,localhost,jump

#### 8.9.3. Configuring HTTP Proxy for the SLC Bridge {#apx-http-proxy-slcb}

The SLC Bridge binary shall use the proxy settings from the environment on *management host* [configured earlier](#apx-http-proxy-management-host). This is important to allow SLCB to talk to the SAP image registry (proxied), local image registry and OpenShift API (not proxied).

During SLC Bridge's init phase, which deploys the bridge as a container on the OpenShift cluster, one must set Proxy settings as well when prompted. Here are the example values:

    # ./slcb init
    ...
    ***************************************************************************
    * Choose whether you want to run the deployment in typical or expert mode *
    ***************************************************************************

         1. Typical Mode
       > 2. Expert Mode
    Choose action <F12> for Back/<F1> for help
      possible values [1,2]: 2
    ...
    ************************
    *    Proxy Settings    *
    ************************

       Configure Proxy Settings: y
    Choose action <F12> for Back/<F1> for help
      possible values [yes(y)/no(n)]: y

    ************************
    *     HTTPS Proxy      *
    ************************

    Enter the URL of the HTTPS Proxy to use
    Choose action <F12> for Back/<F1> for help
      HTTPS Proxy: http://proxy.example.com:3128

So far no surprise. For the `No Proxy` however, it is recommended to copy&append the `.status.noProxy` settings from the [OpenShift's proxy object](#apx-http-proxy-ocp).

    ************************
    *   Cluster No Proxy   *
    ************************

    Specify the NO_PROXY setting for the cluster.
    The value cannot contain white space and it must be comma-separated.
    You have to include the address range configured for the kubernetes cluster in this list (e.g. "10.240.0.0/20").
    Choose action <F12> for Back/<F1> for help
      Cluster No Proxy: 10.128.0.0/14,127.0.0.1,172.30.0.0/16,192.168.128.0/24,localhost,jump,169.254.169.254,sap-slcbridge,.local,.example.com,.svc,.internal

**Note**: you can use the following script to generate the value from OpenShift's proxy settings.

    # bash <(curl -s https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/utils/get_no_proxy.sh) --slcb

Please make sure to append the `--slcb` paramater.

#### 8.9.4. Configuring HTTP Proxy for the SAP DI during its installation {#apx-http-proxy-di-install}

During the [SDI installation](#sdi-install-with-slcb), one must choose the "Advanced Installation" for the "Installation Type" in order to configure Proxy.

Then the following is the example of proxy settings:

    **************************
    * Cluster Proxy Settings *
    **************************

       Choose if you want to configure proxy settings on the cluster: y
    Choose action <F12> for Back/<F1> for help
      possible values [yes(y)/no(n)]: y

    ************************
    *  Cluster HTTP Proxy  *
    ************************

    Specify the HTTP_PROXY value for the cluster.
    Choose action <F12> for Back/<F1> for help
      HTTP_PROXY: http://proxy.example.com:3128

    ************************
    * Cluster HTTPS Proxy  *
    ************************

    Specify the HTTPS_PROXY value for the cluster.
    Choose action <F12> for Back/<F1> for help
      HTTPS_PROXY: http://proxy.ocpoff.vslen:3128

    ************************
    *   Cluster No Proxy   *
    ************************

    Specify the NO_PROXY value for the cluster. NO_PROXY value cannot contain white spaces and it must be comma-separated.
    Choose action <F12> for Back/<F1> for help
      NO_PROXY: 10.0.0.0/16,10.128.0.0/14,127.0.0.1,172.30.0.0/16,192.168.0.0/16,192.168.128.2,localhost,jump,169.254.169.254,auditlog,datalake,diagnostics-prometheus-pushgateway,hana-service,storagegateway,uaa,vora-consul,vora-dlog,vora-prometheus-pushgateway,vsystem,vsystem-internal,*.local,*.example.com,*.svc,*.internal

<span id="no-proxy-script-example" markdown="1">**Note**:</span> the value can be generated using the following script:

    # bash <(curl -s https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/utils/get_no_proxy.sh)

    # # to see the usage and options, append `--help`
    # bash <(curl -s https://raw.githubusercontent.com/redhat-sap/sap-data-intelligence/master/utils/get_no_proxy.sh) --help

When setting the `No Proxy`, please mind the following:

- The wildcard domains must contain wildcard character. On the contrary, the [OpenShift's proxy settings](#apx-http-proxy-ocp) must not contain wildcard characters.
- As of SLC Bridge 1.1.72, `NO_PROXY` must not start with a wildcard domain. IOW, please put the wildcard domains at the end of `NO_PROXY`.
- In addition to the OpenShift Proxy's `.status.noProxy` values, the list should include also the following service names:

    - `vora-consul,hana-service,uaa,auditlog,vora-dlog,vsystem-internal,vsystem,vora-prometheus-pushgateway,diagnostics-prometheus-pushgateway,storagegateway,datalake`

#### 8.9.5. Configuring HTTP Proxy after the SAP DI installation {#apx-http-proxy-di-post-install}

1. Login to the `system` tenant as a `clusterAdmin` and open the `System Management`.
2. Click on `Cluster` and then click on `Tenants`.
3. For each tenant, click on the tenant row.
4. Click on the "View Application Configuration and Secrets".
5. Search for `PROXY` and click on the Edit button.
6. Edit the values as needed. Feel free to use the [`get_no_proxy.sh` script above](#no-proxy-script-example) to generate the `No proxy` value.
7. Click the `Update` button.
8. (If dealing with `system` tenant, please skip this step until the very end). Go back to the tenant overview. This time, click on "Delete all Instances". **Note** that this will cause a slight downtime for the tenant's current users.
9. Repeat for other tenants from step 3.
10. Execute step 8 for `system` tenant as well.

## 9. Troubleshooting Tips {#troubleshooting}

### 9.1. Installation, Upgrade and Restore problems {#installation-problems}

#### 9.1.1. Privileged security context unassigned {#privileged-scc-unassigned}

If there are pods, replicasets, or statefulsets not coming up and you can see an event similar to the one below, you need to add *privileged* security context constraint to its service account.

    # oc get events | grep securityContext
    1m          32m          23        diagnostics-elasticsearch-5b5465ffb.156926cccbf56887                          ReplicaSet                                                                            Warning   FailedCreate             replicaset-controller                  Error creating: pods "diagnostics-elasticsearch-5b5465ffb-" is forbidden: unable to validate against any security context constraint: [spec.initContainers[0].securityContext.privileged: Invalid value: true: Privileged containers are not allowed spec.initContainers[0].securityContext.privileged: Invalid value: true: Privileged containers are not allowed spec.initContainers[0].securityContext.privileged: Invalid value: true: Privileged containers are not allowed]

Copy the name in the fourth column (the event name - `diagnostics-elasticsearch-5b5465ffb.156926cccbf56887`) and determine its corresponding service account name.

    # eventname="diagnostics-elasticsearch-5b5465ffb.156926cccbf56887"
    # oc get -o go-template=$'{{with .spec.template.spec.serviceAccountName}}{{.}}{{else}}default{{end}}\n' \
        "$(oc get events "${eventname}" -o jsonpath='{.involvedObject.kind}/{.involvedObject.name}{"\n"}')"
    sdi-elasticsearch

The obtained service account name (`sdi-elasticsearch`) now needs to be assigned *privileged* SCC:

    # oc adm policy add-scc-to-user privileged -z sdi-elasticsearch

The pod then shall come up on its own unless this was the only problem.

#### 9.1.2. No Default Storage Class set {#no-default-storage-class-set}

If pods are failing because because of PVCs not being bound, the problem may be that the default storage class has not been set and no storage class was specified to the installer.

    # oc get pods
    NAME                                                  READY     STATUS    RESTARTS   AGE
    hana-0                                                0/1       Pending   0          45m
    vora-consul-0                                         0/1       Pending   0          45m
    vora-consul-1                                         0/1       Pending   0          45m
    vora-consul-2                                         0/1       Pending   0          45m

    # oc describe pvc data-hana-0
    Name:          data-hana-0
    Namespace:     sdi
    StorageClass:
    Status:        Pending
    Volume:
    Labels:        app=vora
                   datahub.sap.com/app=hana
                   vora-component=hana
    Annotations:   <none>
    Finalizers:    [kubernetes.io/pvc-protection]
    Capacity:
    Access Modes:
    Events:
      Type    Reason         Age                  From                         Message
      ----    ------         ----                 ----                         -------
      Normal  FailedBinding  47s (x126 over 30m)  persistentvolume-controller  no persistent volumes available for this claim and no storage class is set

To fix this, either make sure to set the [Default StorageClass (4.8)](https://docs.openshift.com/container-platform/4.8/storage/dynamic-provisioning.html#storage-class-annotations_dynamic-provisioning) / [(4.6)](https://docs.openshift.com/container-platform/4.6/storage/dynamic-provisioning.html#storage-class-annotations_dynamic-provisioning) or provide the storage class name to the installer.

#### 9.1.3. vsystem-app pods not coming up {#vsystem-app-pods-not-starting}

If you have SELinux in enforcing mode you may see the pods launched by vsystem crash-looping because of the container named `vsystem-iptables` like this:

    # oc get pods
    NAME                                                          READY     STATUS             RESTARTS   AGE
    auditlog-59b4757cb9-ccgwh                                     1/1       Running            0          40m
    datahub-app-db-gzmtb-67cd6c56b8-9sm2v                         2/3       CrashLoopBackOff   11         34m
    datahub-app-db-tlwkg-5b5b54955b-bb67k                         2/3       CrashLoopBackOff   10         30m
    ...
    internal-comm-secret-gen-nd7d2                                0/1       Completed          0          36m
    license-management-gjh4r-749f4bd745-wdtpr                     2/3       CrashLoopBackOff   11         35m
    shared-k98sh-7b8f4bf547-2j5gr                                 2/3       CrashLoopBackOff   4          2m
    ...
    vora-tx-lock-manager-7c57965d6c-rlhhn                         2/2       Running            3          40m
    voraadapter-lsvhq-94cc5c564-57cx2                             2/3       CrashLoopBackOff   11         32m
    voraadapter-qkzrx-7575dcf977-8x9bt                            2/3       CrashLoopBackOff   11         35m
    vsystem-5898b475dc-s6dnt                                      2/2       Running            0          37m

When you inspect one of those pods, you can see an error message similar to the one below:

    # oc logs voraadapter-lsvhq-94cc5c564-57cx2 -c vsystem-iptables
    2018-12-06 11:45:16.463220|+0000|INFO |Execute: iptables -N VSYSTEM-AGENT-PREROUTING -t nat||vsystem|1|execRule|iptables.go(56)
    2018-12-06 11:45:16.465087|+0000|INFO |Output: iptables: Chain already exists.||vsystem|1|execRule|iptables.go(62)
    Error: exited with status: 1
    Usage:
      vsystem iptables [flags]

    Flags:
      -h, --help               help for iptables
          --no-wait            Exit immediately after applying the rules and don't wait for SIGTERM/SIGINT.
          --rule stringSlice   IPTables rule which should be applied. All rules must be specified as string and without the iptables command.

And in the audit log on the node, where the pod got scheduled, you should be able to find an AVC denial similar to the following. On RHCOS nodes, you may need to inspect the output of `dmesg` command instead.

    # grep 'denied.*iptab' /var/log/audit/audit.log
    type=AVC msg=audit(1544115868.568:15632): avc:  denied  { module_request } for  pid=54200 comm="iptables" kmod="ipt_REDIRECT" scontext=system_u:system_r:container_t:s0:c826,c909 tcontext=system_u:system_r:kernel_t:s0 tclass=system permissive=0
    ...
    # # on RHCOS
    # dmesg | grep denied

To fix this, the `ipt_REDIRECT` kernel module needs to be loaded. Please refer to [Pre-load needed kernel modules](#preload-kernel-modules-post).

#### 9.1.4. License Manager cannot be initialized {#license-manager-cannot-be-initialized}

The installation may fail with the following error.

    2019-07-22T15:07:29+0000 [INFO] Initializing system tenant...
    2019-07-22T15:07:29+0000 [INFO] Initializing License Manager in system tenant...2019-07-22T15:07:29+0000 [ERROR] Couldn't start License Manager!
    The response: {"status":500,"code":{"component":"router","value":8},"message":"Internal Server Error: see logs for more info"}Error: http status code 500 Internal Server Error (500)
    2019-07-22T15:07:29+0000 [ERROR] Failed to initialize vSystem, will retry in 30 sec...

In the log of license management pod, you can find an error like this:

    # oc logs deploy/license-management-l4rvh
    Found 2 pods, using pod/license-management-l4rvh-74595f8c9b-flgz9
    + iptables -D PREROUTING -t nat -j VSYSTEM-AGENT-PREROUTING
    + true
    + iptables -F VSYSTEM-AGENT-PREROUTING -t nat
    + true
    + iptables -X VSYSTEM-AGENT-PREROUTING -t nat
    + true
    + iptables -N VSYSTEM-AGENT-PREROUTING -t nat
    iptables v1.6.2: can't initialize iptables table `nat': Permission denied
    Perhaps iptables or your kernel needs to be upgraded.

This means, the `vsystem-iptables` container in the pod lacks permissions to manipulate iptables. Please make sure to [pre-load kernel modules](#preload-kernel-modules-post).

#### 9.1.5. Diagnostics Prometheus Node Exporter pods not starting {#node-exporter-pods-not-starting}

During an installation or upgrade, it may happen, that the Node Exporter pods keep restarting:

    # oc get pods  | grep node-exporter
    diagnostics-prometheus-node-exporter-5rkm8                        0/1       CrashLoopBackOff   6          8m
    diagnostics-prometheus-node-exporter-hsww5                        0/1       CrashLoopBackOff   6          8m
    diagnostics-prometheus-node-exporter-jxxpn                        0/1       CrashLoopBackOff   6          8m
    diagnostics-prometheus-node-exporter-rbw82                        0/1       CrashLoopBackOff   7          8m
    diagnostics-prometheus-node-exporter-s2jsz                        0/1       CrashLoopBackOff   6          8m

The possible reason is that the limits on resource consumption set on the pods are too low. To address this post-installation, you can patch the DaemonSet like this (in the SDI's namespace):

    # oc patch -p '{"spec": {"template": {"spec": {"containers": [
        { "name": "diagnostics-prometheus-node-exporter",
          "resources": {"limits": {"cpu": "200m", "memory": "100M"}}
        }]}}}}' ds/diagnostics-prometheus-node-exporter

To address this during the installation (using any installation method), add the following parameters:

    -e=vora-diagnostics.resources.prometheusNodeExporter.resources.limits.cpu=200m
    -e=vora-diagnostics.resources.prometheusNodeExporter.resources.limits.memory=100M

#### 9.1.6. Builds are failing in the Pipeline Modeler {#tshoot-link-vflow-secret}

If the graph builds hang in `Pending` state or fail completely, you may find the following pod not coming up in the `sdi` namespace because its image cannot be pulled from the registry:

    # oc get pods | grep vflow
    datahub.post-actions.validations.validate-vflow-9s25l             0/1     Completed          0          14h
    vflow-bus-fb1d00052cc845c1a9af3e02c0bc9f5d-5zpb2                  0/1     ImagePullBackOff   0          21s
    vflow-graph-9958667ba5554dceb67e9ec3aa6a1bbb-com-sap-demo-dljzk   1/1     Running            0          94m
    # oc describe pod/vflow-bus-fb1d00052cc845c1a9af3e02c0bc9f5d-5zpb2 | sed -n '/^Events:/,$p'
    Events:
      Type     Reason     Age                From                    Message
      ----     ------     ----               ----                    -------
      Normal   Scheduled  30s                default-scheduler       Successfully assigned sdi/vflow-bus-fb1d00052cc845c1a9af3e02c0bc9f5d-5zpb2 to sdi-moworker3
      Normal   BackOff    20s (x2 over 21s)  kubelet, sdi-moworker3  Back-off pulling image "container-image-registry-sdi-observer.apps.morrisville.ocp.vslen/sdi3modeler-blue/vora/vflow-node-f87b598586d430f955b09991fc1173f716be17b9:3.0.23-com.sap.sles.base-20200617-174600"
      Warning  Failed     20s (x2 over 21s)  kubelet, sdi-moworker3  Error: ImagePullBackOff
      Normal   Pulling    6s (x2 over 21s)   kubelet, sdi-moworker3  Pulling image "container-image-registry-sdi-observer.apps.morrisville.ocp.vslen/sdi3modeler-blue/vora/vflow-node-f87b598586d430f955b09991fc1173f716be17b9:3.0.23-com.sap.sles.base-20200617-174600"
      Warning  Failed     6s (x2 over 21s)   kubelet, sdi-moworker3  Failed to pull image "container-image-registry-sdi-observer.apps.morrisville.ocp.vslen/sdi3modeler-blue/vora/vflow-node-f87b598586d430f955b09991fc1173f716be17b9:3.0.23-com.sap.sles.base-20200617-174600": rpc error: code = Unknown desc = Error reading manifest 3.0.23-com.sap.sles.base-20200617-174600 in container-image-registry-sdi-observer.apps.morrisville.ocp.vslen/sdi3modeler-blue/vora/vflow-node-f87b598586d430f955b09991fc1173f716be17b9: unauthorized: authentication required
      Warning  Failed     6s (x2 over 21s)   kubelet, sdi-moworker3  Error: ErrImagePull

To amend this, one needs to link the secret for the modeler's registry to a corresponding service account associated with the failed pod. In this case, the `default` one.

    # oc get -n "${SDI_NAMESPACE:-sdi}" -o jsonpath='{.spec.serviceAccountName}{"\n"}' \
        pod/vflow-bus-fb1d00052cc845c1a9af3e02c0bc9f5d-5zpb2
    default
    # oc create secret -n "${SDI_NAMESPACE:-sdi}" docker-registry sdi-registry-pull-secret \
        --docker-server=container-image-registry-sdi-observer.apps.morrisville.ocp.vslen \
        --docker-username=user-n5137x --docker-password=ec8srNF5Pf1vXlPTRLagEjRRr4Vo3nIW
    # oc secrets link -n "${SDI_NAMESPACE:-sdi}" --for=pull default sdi-registry-pull-secret
    # oc delete -n "${SDI_NAMESPACE:-sdi}" pod/vflow-bus-fb1d00052cc845c1a9af3e02c0bc9f5d-5zpb2

Also please make sure to restart the Pipeline Modeler and failing graph builds in the offended tenant.

#### 9.1.7. Container fails with "Permission denied" {#tshoot-anyuid-unapplied}

If pods fail with a similar error like the one below, the containers most probably are not allowed to run under desired UID.

    # oc get pods
    NAME                                READY   STATUS             RESTARTS   AGE
    datahub.checks.checkpoint-m82tj     0/1     Completed          0          12m
    vora-textanalysis-6c9789756-pdxzd   0/1     CrashLoopBackOff   6          9m18s
    # oc logs vora-textanalysis-6c9789756-pdxzd
    Traceback (most recent call last):
      File "/dqp/scripts/start_service.py", line 413, in <module>
        sys.exit(Main().run())
      File "/dqp/scripts/start_service.py", line 238, in run
        **global_run_args)
      File "/dqp/python/dqp_services/services/textanalysis.py", line 20, in run
        trace_dir = utils.get_trace_dir(global_trace_dir, self.config)
      File "/dqp/python/dqp_utils.py", line 90, in get_trace_dir
        return get_dir(global_trace_dir, conf.trace_dir)
      File "/dqp/python/dqp_utils.py", line 85, in get_dir
        makedirs(config_value)
      File "/usr/lib64/python2.7/os.py", line 157, in makedirs
        mkdir(name, mode)
    OSError: [Errno 13] Permission denied: 'textanalysis'

To remedy that, be sure to apply all the `oc adm policy add-scc-to-*` commands from the [project setup](#project-setup) section. The one that has not been applied in this case is:

    # oc adm policy add-scc-to-group anyuid "system:serviceaccounts:$(oc project -q)"

#### 9.1.8. Jobs failing during installation or upgrade {#tshoot-jobs-failing}

If the installation jobs are failing with the following error, either `anyuid` security context constraint has not been applied or the cluster is too old.

    # oc logs solution-reconcile-vsolution-vsystem-ui-3.0.9-vnnbf
    Error: mkdir /.vsystem: permission denied.
    2020-03-05T15:51:18+0000 [WARN] Could not login to vSystem!
    2020-03-05T15:51:23+0000 [INFO] Retrying...
    Error: mkdir /.vsystem: permission denied.
    2020-03-05T15:51:23+0000 [WARN] Could not login to vSystem!
    2020-03-05T15:51:28+0000 [INFO] Retrying...
    Error: mkdir /.vsystem: permission denied.
    ...
    2020-03-05T15:52:13+0000 [ERROR] Timeout while waiting to login to vSystem...

The reason behind is that `vctl` binary in the containers determines `HOME` directory for its user from `/etc/passwd`. When the container is not run with the desired UID, the value is set incorrectly to `/`. The binary then lacks permissions to write to the root directory.

To remedy that, please make sure:

1. you are running OpenShift cluster 4.2.32 or newer
2. [anyuid SCC has been applied to the SDI namespace](#tshoot-anyuid-unapplied)

   To verify, make sure the SDI namespace is listed in the 3rd column of the output of the following command:

        # oc get -o json scc/anyuid | jq -r '.groups[]'
        system:cluster-admins
        system:serviceaccounts:sdi

   When the jobs will be rerun, `anyuid` scc will be assigned to them:

        # oc get pods -n "${SDI_NAMESPACE:-sdi}" -o json | jq -r '.items[] | select((.metadata.ownerReferences // []) |
            any(.kind == "Job")) | "\(.metadata.name)\t\(.metadata.annotations["openshift.io/scc"])"' | column -t
        datahub.voracluster-start-1d3ffe-287c16-d7h7t                    anyuid
        datahub.voracluster-start-b3312c-287c16-j6g7p                    anyuid
        datahub.voracluster-stop-5a6771-6d14f3-nnzkf                     anyuid
        ...
        strategy-reconcile-strat-system-3.0.34-3.0.34-pzn79              anyuid
        tenant-reconcile-default-3.0.34-wjlfs                            anyuid
        tenant-reconcile-system-3.0.34-gf7r4                             anyuid
        vora-config-init-qw9vc                                           anyuid
        vora-dlog-admin-f6rfg                                            anyuid

3. additionally, please make sure that all the other `oc adm policy add-scc-to-*` commands listed in the [project setup](#project-setup) have been applied to the same `$SDI_NAMESPACE`.

#### 9.1.9. vsystem-vrep cannot export NFS on RHCOS {#tshoot-vrep-nfs-server-fail}

If `vsystem-vrep-0` pod fails with the following error, it means it is unable to start an NFS server on top of overlayfs.

    # oc logs -n ocpsdi1 vsystem-vrep-0 vsystem-vrep
    2020-07-13 15:46:05.054171|+0000|INFO |Starting vSystem version 2002.1.15-0528, buildtime 2020-05-28T18:5856, gitcommit ||vsystem|1|main|server.go(107)
    2020-07-13 15:46:05.054239|+0000|INFO |Starting Kernel NFS Server||vrep|1|Start|server.go(83)
    2020-07-13 15:46:05.108868|+0000|INFO |Serving liveness probe at ":8739"||vsystem|9|func2|server.go(149)
    2020-07-13 15:46:10.303625|+0000|WARN |no backup or restore credentials mounted, not doing backup and restore||vsystem|1|NewRcloneBackupRestore|backup_restore.go(76)
    2020-07-13 15:46:10.311488|+0000|INFO |vRep components are initialised successfully||vsystem|1|main|server.go(249)
    2020-07-13 15:46:10.311617|+0000|ERROR|cannot parse duration from "SOLUTION_LAYER_CLEANUP_DELAY" env variable: time: invalid duration ||vsystem|16|CleanUpSolutionLayersJob|manager.go(351)
    2020-07-13 15:46:10.311719|+0000|INFO |Background task for cleaning up solution layers will be triggered every 12h0m0s||vsystem|16|CleanUpSolutionLayersJob|manager.go(358)
    2020-07-13 15:46:10.312402|+0000|INFO |Recreating volume mounts||vsystem|1|RemountVolumes|volume_service.go(339)
    2020-07-13 15:46:10.319334|+0000|ERROR|error re-loading NFS exports: exit status 1
    exportfs: /exports does not support NFS export||vrep|1|AddExportsEntry|server.go(162)
    2020-07-13 15:46:10.319991|+0000|FATAL|Error creating runtime volume: error exporting directory for runtime data via NFS: export error||vsystem|1|Fail|termination.go(22)

There are two solutions to the problem. Both of them resulting in an additional volume mounted at `/exports` which is the root directory of all exports.

- *(recommended)* deploy [SDI Observer](#sdi-observer) which will request additional persistent volume of size 500Mi for `vsystem-vrep-0` pod and make sure it is running
- add `-e=vsystem.vRep.exportsMask=true` to the [`Additional Installer Parameters`](#sdi-installation-parameters) which will mount `emptyDir` volume at `/exports` in the same pod

#### 9.1.10. Kaniko cannot push images to a registry {#tshoot-blob-upload-unknown}

**Symptoms**:

- kaniko is enabled in SDI *(mandatory on OpenShift 4)*
- registry is secured by TLS certificates with a self-signed certificate
- other SDI and OpenShift components can use the registry without issues
- the pipeline modeler crashes with a traceback preceded with the following error:

        # oc logs -f -c vflow  "$(oc get pods -o name \
          -l vsystem.datahub.sap.com/template=pipeline-modeler | head -n 1)" | grep 'push permissions'
        error checking push permissions -- make sure you entered the correct tag name, and that you are authenticated correctly, and try again: checking push permission for "container-image-registry-miminar-sdi-observer.apps.sydney.example.com/vora/vflow-node-f87b598586d430f955b09991fc11
        73f716be17b9:3.0.27-com.sap.sles.base-20201001-102714": BLOB_UPLOAD_UNKNOWN: blob upload unknown to registry

**Resolution**:

The root cause has not been identified yet. To work-around it, modeler shall be configured to use insecure registry accessible via plain HTTP (without TLS) and requiring no authentication. Such a registry can be [provisioned with SDI Observer](#sdi-observer-registry). If the existing registry is provisioned by SDI Observer, one can modify it to require no authentication like this:

1. [Initiate an update of SDI Observer](#sdi-observer-redeploy).
2. Re-configure sdi-observer for no authentication:

        # oc set env -n "${NAMESPACE:-sdi-observer}" SDI_REGISTRY_AUTHENTICATION=none dc/sdi-observer

3. Wait until the registry gets re-deployed.
4. Verify that the registry is running and that neither `REGISTRY_AUTH_HTPASSWD_REALM` nor `REGISTRY_AUTH_HTPASSWD_PATH` are present in the output of the following command:

        # oc set env -n "${NAMESPACE:-sdi-observer}" --list dc/container-image-registry
        REGISTRY_HTTP_SECRET=mOjuXMvQnyvktGLeqpgs5f7nQNAiNMEE

5. Note the registry service address which can be determined like this:

        # # <service-name>.<namespace>.cluster.local:<service-port>
        # oc project "${NAMESPACE:-sdi-observer}"
        # printf "$(oc get -o jsonpath='{.metadata.name}.{.metadata.namespace}.svc.%s:{.spec.ports[0].port}' \
                svc container-image-registry)\n" \
            "$(oc get dnses.operator.openshift.io/default -o jsonpath='{.status.clusterDomain}')"
        container-image-registry.sdi-observer.svc.cluster.local:5000

6. Verify that the service is responsive over plain HTTP from inside of the OpenShift cluster and requires no authentication:

        # registry_url=http://container-image-registry.sdi-observer.svc.cluster.local:5000
        # oc rsh -n openshift-authentication "$(oc get pods -n openshift-authentication | \
            awk '/oauth-openshift.*Running/ {print $1; exit}')" curl -I "$registry_url"
        HTTP/1.1 200 OK
        Content-Length: 2
        Content-Type: application/json; charset=utf-8
        Docker-Distribution-Api-Version: reg

   **Note**: the service URL is not reachable from outside of the OpenShift cluster

7. For each SDI tenant using the registry:

    1. Login to the tenant as an administrator and open System Management.
    2. View Application Configuration and Secrets.

       ![Access Application Configuration and Secrets](/sites/default/files/images/app-configuration-and-secrets.png "Access Application Configuration and Secrets")

    3. Set the following properties to the registry address:

        - Modeler: Base registry for pulling images
        - Modeler: Docker registry for Modeler images

    4. Unset the following properties:

        - Modeler: Name of the vSystem secret containing the credentials for Docker registry
        - Modeler: Docker image pull secret for Modeler

       The end result should look like:

       ![Modified registry parameters for Modeler](/sites/default/files/images/pipeline-modeler-no-auth-registry-config.png "Modified registry parameters for Modeler")

    5. Return to the "Applications" in the System Management and select Modeler.
    6. Delete all the instances.
    7. Create a new instance with the plus button.
    8. Access the instance to verify it is working.

#### 9.1.11. SLCBridge pod fails to deploy {#tshoot-slcb-1153}

If the initialisation phase of Software Lifecycle Container Bridge fails with an error like the one below, you are probably running SLCB version 1.1.53 configured to push to a registry requiring basic authentication.

    *************************************************
    * Executing Step WaitForK8s SLCBridgePod Failed *
    *************************************************

      Execution of step WaitForK8s SLCBridgePod failed
      Synchronizing Deployment slcbridgebase failed (pod "slcbridgebase-5bcd7946f4-t6vfr" failed) [1.116647047s]
      .
      Choose "Retry" to retry the step.
      Choose "Rollback" to undo the steps done so far.
      Choose "Cancel" to cancel deployment immediately.

    # oc logs -n sap-slcbridge -c slcbridge -l run=slcbridge --tail=13
    ----------------------------
    Code: 401
    Scheme: basic
    "realm": "basic-realm"
    {"errors":[{"code":"UNAUTHORIZED","message":"authentication required","detail":null}]}
    ----------------------------
    2020-09-29T11:49:33.346Z        INFO    images/registry.go:182  Access check of registry "container-image-registry-sdi-observer.apps.sydney.example.com" returned AuthNeedBasic
    2020-09-29T11:49:33.346Z        INFO    slp/server.go:199       Shutting down server
    2020-09-29T11:49:33.347Z        INFO    hsm/hsm.go:125  Context closed
    2020-09-29T11:49:33.347Z        INFO    hsm/state.go:56 Received Cancel
    2020-09-29T11:49:33.347Z        DEBUG   hsm/hsm.go:118  Leaving event loop
    2020-09-29T11:49:33.347Z        INFO    slp/server.go:208       Server shutdown complete
    2020-09-29T11:49:33.347Z        INFO    slcbridge/master.go:64  could not authenticate at registry SLP_BRIDGE_REPOSITORY container-image-registry-sdi-observer.apps.sydney.example.com
    2020-09-29T11:49:33.348Z        INFO    globals/goroutines.go:63        Shutdown complete (exit status 1).

More information can be found in [SAP Note #2589449](https://launchpad.support.sap.com/#/notes/2589449).

To fix this, please download the latest SLCB version newer than 1.1.53 according to the [SAP Note #2589449](https://launchpad.support.sap.com/#/notes/2589449)

#### 9.1.12. Kibana pod fails to start {#tshoot-kibana-fails}

When kibana pod is stuck in `CrashLoopBackOff` status, and the following error shows up in its log, you will need to delete the existing index.

    # oc logs -n "${SDI_NAMESPACE:-sdi}" -c diagnostics-kibana -l datahub.sap.com/app-component=kibana --tail=5
    {"type":"log","@timestamp":"2020-10-07T14:40:23Z","tags":["status","plugin:ui_metric@7.3.0-SNAPSHOT","info"],"pid":1,"state":"green","message":"Status changed from uninitialized to green - Ready","prevState":"uninitialized","prevMsg":"uninitialized"}
    {"type":"log","@timestamp":"2020-10-07T14:40:23Z","tags":["status","plugin:visualizations@7.3.0-SNAPSHOT","info"],"pid":1,"state":"green","message":"Status changed from uninitialized to green - Ready","prevState":"uninitialized","prevMsg":"uninitialized"}
    {"type":"log","@timestamp":"2020-10-07T14:40:23Z","tags":["status","plugin:elasticsearch@7.3.0-SNAPSHOT","info"],"pid":1,"state":"green","message":"Status changed from yellow to green - Ready","prevState":"yellow","prevMsg":"Waiting for Elasticsearch"}
    {"type":"log","@timestamp":"2020-10-07T14:40:23Z","tags":["info","migrations"],"pid":1,"message":"Creating index .kibana_1."}
    {"type":"log","@timestamp":"2020-10-07T14:40:23Z","tags":["warning","migrations"],"pid":1,"message":"Another Kibana instance appears to be migrating the index. Waiting for that migration to complete. If no other Kibana instance is attempting migrations, you can get past this message by deleting index .kibana_1 and restarting Kibana."}

Please note the name of the index in the last warning message. In this case it is `.kibana_1`. Execute the following command with the proper index name at the end of the curl command to delete the index and then delete the kibana pod as well.

    # oc exec -n "${SDI_NAMESPACE:-sdi}" -it diagnostics-elasticsearch-0 -c diagnostics-elasticsearch \
        -- curl -X DELETE 'http://localhost:9200/.kibana_1'
    # oc delete pod -n "${SDI_NAMESPACE:-sdi}" -l datahub.sap.com/app-component=kibana

The kibana pod will be spawned and shall become Running in few minutes as long as its dependent diagnostics pods are running as well.

#### 9.1.13. Fluentd pods cannot access /var/lib/docker/containers {#fluentd-pods-cannot-access-logs}

If you see the following errors, the fluentd cannot access container logs on the hosts.

- Error from SLC Bridge:

        2021-01-26T08:28:49.810Z  INFO  cmd/cmd.go:243  1> DataHub/kub-slcbridge/default [Pending]
        2021-01-26T08:28:49.810Z  INFO  cmd/cmd.go:243  1> └── Diagnostic/kub-slcbridge/default [Failed]  [Start Time:  2021-01-25 14:26:03 +0000 UTC]
        2021-01-26T08:28:49.811Z  INFO  cmd/cmd.go:243  1>     └── DiagnosticDeployment/kub-slcbridge/default [Failed]  [Start Time:  2021-01-25 14:26:29 +0000 UTC]
        2021-01-26T08:28:49.811Z  INFO  cmd/cmd.go:243  1>
        2021-01-26T08:28:55.989Z  INFO  cmd/cmd.go:243  1> DataHub/kub-slcbridge/default [Pending]
        2021-01-26T08:28:55.989Z  INFO  cmd/cmd.go:243  1> └── Diagnostic/kub-slcbridge/default [Failed]  [Start Time:  2021-01-25 14:26:03 +0000 UTC]
        2021-01-26T08:28:55.989Z  INFO  cmd/cmd.go:243  1>     └── DiagnosticDeployment/kub-slcbridge/default [Failed]  [Start Time:  2021-01-25 14:26:29 +0000 UTC]

- Fluentd pod description:

        # oc describe pod diagnostics-fluentd-bb9j7
        Name:           diagnostics-fluentd-bb9j7
        …
          Warning  FailedMount  6m35s                 kubelet, compute-4  Unable to attach or mount volumes: unmounted volumes=[varlibdockercontainers], unattached volumes=[vartmp kub-slcbridge-fluentd-token-k5c9n settings varlog varlibdockercontainers]: timed out waiting for the condition
          Warning  FailedMount  2m1s (x2 over 4m19s)  kubelet, compute-4  Unable to attach or mount volumes: unmounted volumes=[varlibdockercontainers], unattached volumes=[varlibdockercontainers vartmp kub-slcbridge-fluentd-token-k5c9n settings varlog]: timed out waiting for the condition
          Warning  FailedMount  23s (x12 over 8m37s)  kubelet, compute-4  MountVolume.SetUp failed for volume "varlibdockercontainers" : hostPath type check failed: /var/lib/docker/containers is not a directory

- Log from one of the pods:

        # oc logs $(oc get pods -o name -l datahub.sap.com/app-component=fluentd | head -n 1) | tail -n 20
          2019-04-15 18:53:24 +0000 [error]: unexpected error error="Permission denied @ rb_sysopen - /var/log/es-containers-sdh25-mortal-garfish.log.pos"
          2019-04-15 18:53:24 +0000 [error]: suppressed same stacktrace
          2019-04-15 18:53:25 +0000 [warn]: '@' is the system reserved prefix. It works in the nested configuration for now but it will be rejected: @timestamp
          2019-04-15 18:53:26 +0000 [error]: unexpected error error_class=Errno::EACCES error="Permission denied @ rb_sysopen - /var/log/es-containers-sdh25-mortal-garfish.log.pos"
          2019-04-15 18:53:26 +0000 [error]: /usr/lib64/ruby/gems/2.5.0/gems/fluentd-0.14.8/lib/fluent/plugin/in_tail.rb:151:in `initialize'
          2019-04-15 18:53:26 +0000 [error]: /usr/lib64/ruby/gems/2.5.0/gems/fluentd-0.14.8/lib/fluent/plugin/in_tail.rb:151:in `open'
        ...

Those errors are fixed automatically by SDI Observer, please make sure it is running and can access the `SDI_NAMESPACE`.

One can also apply a fix manually with the following commands:

    # oc -n "${SDI_NAMESPACE:-sdi}" patch dh default --type='json' -p='[
        { "op": "replace"
        , "path": "/spec/diagnostic/fluentd/varlibdockercontainers"
        , "value":"/var/log/pods" }]'
    # oc -n "${SDI_NAMESPACE:-sdi}" patch ds/diagnostics-fluentd -p '{"spec":{"template":{"spec":{
        "containers": [{"name":"diagnostics-fluentd", "securityContext":{"privileged": true}}]}}}}'

#### 9.1.14. Validation of vflow fails during the SDI installation {#tshoot-post-actions-validate-vflow}

If the following error message is displayed at the end of SDI installation, it means that the pipeline modeler cannot communicate with the configured registry.

    ************************************
    * Executing Step Validation Failed *
    ************************************


    Execution of step Validation failed
    execution failed: status 1, error: time="2021-10-18T13:49:13Z" level=error msg="Job execution failed for job:
    datahub.post-actions.validations.validate-vflow, job failed with reason BackoffLimitExceeded:Job has reached the specified
    backoff limit"
    time="2021-10-18T13:49:13Z" level=error msg="Running script post-actions.validations.validate-vflow...Failed!"
    time="2021-10-18T13:49:13Z" level=error msg="Error: job failed with reason BackoffLimitExceeded:Job has reached the
    specified backoff limit"
    time="2021-10-18T13:50:00Z" level=error msg="Running post-actions/validations...Failed!"
    time="2021-10-18T13:50:00Z" level=fatal msg="Failed: there are failed scripts: post-actions.validations.validate-vflow"
    .
    Choose "Retry" to retry the step.
    Choose "Abort" to abort the SLC Bridge and return to the "Welcome" dialog.
    Choose "Cancel" to cancel the SLC Bridge immediately.

      Choose action Retry(r)/Abort(a)/<F1> for help: n

Often, it is due to registry's CA certificate not being imported properly.

**Verification**

To verify that the certificate is correct, perform the following steps. If any of the steps fails, the certificate must be (re-)configured.

1. From the *Management host*, get the configured certificate from the SDI namespace:

        # oc get -n "${SDI_NAMESPACE:-sdi}" secret/cmcertificates \
                -o jsonpath='{.data.cert}' | base64 -d >cmcertificates.crt

2. Verify the connection to the registry and its trustworthiness:

        # curl --cacert cmcertificates.crt -I https://<configured-registry-for-pipeline-modeler>/v2/

   Example output for a trusted registry:

        HTTP/1.1 200 OK
        Content-Length: 2
        Content-Type: application/json; charset=utf-8
        Docker-Distribution-Api-Version: registry/2.0
        Date: Mon, 18 Oct 2021 14:55:37 GMT

**Resolution**

Update the trusted CA certificates.

1. Ensure the registry is trusted with the correct CA bundle file:

        # curl --cacert correct-ca-bundle.crt -I https://<configured-registry-for-pipeline-modeler>/v2/

2. (*optional*) Update the secret directly or indirectly.

    - Directly.

            # oc create -n "${SDI_NAMESPACE:-sdi}" secret generic cmcertificates \
                    --from-file=cert=correct-ca-bundle.crt --dry-run=client -o json | \
                oc apply -f -

    - Indirectly using SDI Observer:

        1. update the `run-observer-template.sh` for `CABUNDLE_PATH=./correct-ca-bundle.crt` and `INJECT_CABUNDLE=true`
        2. re-run the `run-observer-template.sh` script

3. Follow the [Manage Certificates guide (3.2)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.2.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) / [(3.1)](https://help.sap.com/viewer/b13b5722c8ff4bf9bb097251310031d0/3.1.latest/en-US/95b577f233ea4546ac7620b607fd1f70.html) to import the `correct-ca-bundle.crt` via the SDI Connection Management.
4. Re-run the validation in the Software Lifecycle Bridge.

#### 9.1.15. Vora components are stuck after restore {#tshoot-vora-disk-crashing}

**Symptoms**

- After a restoration from backup, vora pods keep crashing and restarting:

        NAME                                   READY   STATUS      RESTARTS   AGE   IP             NODE            NOMINATED NODE   READINESS GATES
        vora-disk-0                            1/2     Running     3          37m   10.131.1.194   sdi-siworker1   <none>           <none>
        vora-relational-86b67c64b6-gn4pp       1/2     Running     7          37m   10.131.1.190   sdi-siworker1   <none>           <none>
        vora-tx-coordinator-5c6b45bb7b-qqnpn   1/2     Running     7          37m   10.130.2.249   sdi-siworker2   <none>           <none>

- `vora-disk-0` pod does not produce any output:

        # oc logs -c disk -f vora-disk-0

- Local connection to vora-tx-coordinator cannot be established.

**Resolution**

Is described in [SAP Note 2918288 - SAP Data Intelligence Backup and Restore Note](https://launchpad.support.sap.com/#/notes/2918288) in the section `d030326, DIBUGS-11651, 2021-11-09` "Restoration fails with error in Vora disk engine".

#### 9.1.16. Image Mirroring to Quay fails {#tshoot-quay-slcb-push-unauthorized}

During image mirroring to a local Quay registry, it may happen that an upload of a blob fails with the error message below. This is a [known bug on Quay side](https://issues.redhat.com/browse/PROJQUAY-2932) and will be addressed in future versions.

```
writing blob: initiating layer upload to /v2/sdimorrisville/com.sap.datahub.linuxx86_64/datahub-operator-installer-base/blobs/uploads/ in quay.apps.cluster.example.com: unauthorized: access to the requested resource is not authorized
```

Please retry the image mirroring until all the SAP images are successfully mirrored.

#### 9.1.17. SLC Bridge init fails with Quay {#tshoot-quay-slcb-init-imagepullbackoff}

As of SLC Bridge 1.1.71, the pull secrets are not created on OpenShift side as long as a docker authentication file on the *Management host* contains quay registry.

**Symptoms**

- SLC Bridge init fails with the error like the one below:

        *************************************************
        * Executing Step WaitForK8s SLCBridgePod Failed *
        *************************************************

        Execution of step WaitForK8s SLCBridgePod failed
        Synchronizing Deployment slcbridgebase failed (pod "slcbridgebase-6f985dcb87-6plql" failed) [517.957512ms]
        .
        Choose "Retry" to retry the step.
        Choose "Abort" to abort the SLC Bridge and return to the "Welcome" dialog.
        Choose "Cancel" to cancel the SLC Bridge immediately.

          Choose action Retry(r)/Abort(a)/<F1> for help: r

- Pod images in the `sap-slcbridge` namespace cannot be pulled:

        # oc describe pod | sed -n '/^Events:/,$p'
        Events:
          Type     Reason          Age                From               Message
          ----     ------          ----               ----               -------
          Normal   Scheduled       61s                default-scheduler  Successfully assigned slcb-test/slcbridgebase-6f985dcb87-6plql to leworker1.cluster.example.com
          Normal   AddedInterface  61s                multus             Add eth0 [10.131.0.113/23] from openshift-sdn
          Warning  Failed          43s (x2 over 60s)  kubelet            Failed to pull image "quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/nginx-sidecar:1.1.71": rpc error: code = Unknown desc = Error reading manifest 1.1.71 in quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/nginx-sidecar: unauthorized: access to the requested resource is not authorized
          Warning  Failed          43s (x2 over 60s)  kubelet            Error: ErrImagePull
          Normal   Pulling         43s (x2 over 60s)  kubelet            Pulling image "quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/slcbridgebase:1.1.71"
          Warning  Failed          43s (x2 over 60s)  kubelet            Failed to pull image "quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/slcbridgebase:1.1.71": rpc error: code = Unknown desc = Error reading manifest 1.1.71 in quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/slcbridgebase: unauthorized: access to the requested resource is not authorized
          Warning  Failed          43s (x2 over 60s)  kubelet            Error: ErrImagePull
          Normal   BackOff         31s (x3 over 60s)  kubelet            Back-off pulling image "quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/nginx-sidecar:1.1.71"
          Warning  Failed          31s (x3 over 60s)  kubelet            Error: ImagePullBackOff
          Normal   BackOff         31s (x3 over 60s)  kubelet            Back-off pulling image "quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/slcbridgebase:1.1.71"
          Warning  Failed          31s (x3 over 60s)  kubelet            Error: ImagePullBackOff
          Normal   Pulling         20s (x3 over 60s)  kubelet            Pulling image "quay.apps.cluster.example.com/sdi3/com.sap.sl.cbpod/nginx-sidecar:1.1.71"

- No pull secret is present in the `sap-slcbridge` namespace:

        # oc get secret -n slcb-test | grep 'NAME\|pull-secret'
        NAME                        TYPE                                  DATA   AGE

**Resolution**

Please update SLC Bridge to the latest version (at least 1.1.73).

#### 9.1.18. SLC Bridge image fails to be pulled from Quay {#tshoot-quay-slcb-quay-pull-fails}

As of SLC Bridge 1.1.72, the bridge container fails to authenticate to Quay during the registry test.

**Symptoms**

- SLC Bridge init fails with the error like the one below:

        *************************************************
        * Executing Step WaitForK8s SLCBridgePod Failed *
        *************************************************

        Execution of step WaitForK8s SLCBridgePod failed
        Synchronizing Deployment slcbridgebase failed (pod "slcbridgebase-6f985dcb87-6plql" failed) [517.957512ms]
        .
        Choose "Retry" to retry the step.
        Choose "Abort" to abort the SLC Bridge and return to the "Welcome" dialog.
        Choose "Cancel" to cancel the SLC Bridge immediately.

          Choose action Retry(r)/Abort(a)/<F1> for help: r

- The container `slcbridgebase` is crashing.

        # kubectl get pods -n sap-slcbridge
        NAME                             READY   STATUS             RESTARTS   AGE
        slcbridgebase-8488d65d67-tqk7f   0/2     CrashLoopBackOff   25         31m

- Its log contains the following error message:

        # oc logs -l app=slcbridge -c sidecar -n sap-slcbridge | grep unauthorized | head -n 1
        2022-02-11T15:19:29.792Z        WARN    images/registrycheck.go:57      Copying image memtarball:/canary.tar failed: trying to reuse blob sha256:8e0a91696253bb936c9603caed888f624af04b6eb335265a6e7a66e07bd23b51 at destination: checking whether a blob sha256:8e0a91696253bb936c9603caed888f624af04b6eb335265a6e7a66e07bd23b51 exists in quay.apps.lenbarehat.ocp.vslen/sdi172test/com.sap.sl.cbpod/canary: unauthorized: authentication required

**Resolution**

Please update SLC Bridge to the latest version (at least 1.1.73).

### 9.2. SDI Runtime troubleshooting {#tshoot-sdi-runtime}

#### 9.2.1. 504 Gateway Time-out {#tshoot-504-gateway}

When accessing SDI services exposed via OpenShift's Ingress Controller (as routes) and experience 504 Gateway Time-out errors, it is most likely caused by the following factors:

1. SDI components accessed for the first time on a per tenant and per user basis require a new pod to be started which takes a considerable amount of time
2. the default timeout for server connection configured on the load balancers is usually too small to tolerate containers being pulled, initialized and started

To amend that, make sure to do the following:

1. set the `"haproxy.router.openshift.io/timeout"` annotation to `"2m"` on the vsystem route like this (assuming the route is named `vsystem`):

        # oc annotate -n "${SDI_NAMESPACE:-sdi}" route/vsystem haproxy.router.openshift.io/timeout=2m

   This results in the following haproxy settings being applied to the ingress router and the route in question:

        # oc rsh -n openshift-ingress $(oc get pods -o name -n openshift-ingress | \
                awk '/\/router-default/ {print;exit}') cat /var/lib/haproxy/conf/haproxy.config | \
            awk 'BEGIN { p=0 }
                /^backend.*:'"${SDI_NAMESPACE:-sdi}:vsystem"'/ { p=1 }
                { if (p) { print; if ($0 ~ /^\s*$/) {exit} } }'
        Defaulting container name to router.
        Use 'oc describe pod/router-default-6655556d4b-7xpsw -n openshift-ingress' to see all of the containers in this pod.
        backend be_secure:sdi:vsystem
          mode http
          option redispatch
          option forwardfor
          balance leastconn
          timeout server  2m

2. set the same server timeout (2 minutes) on the external load balancer forwarding traffic to OpenShift's Ingress routers; the following is an example configuration for haproxy:

        frontend                                    https
            bind                                    *:443
            mode                                    tcp
            option                                  tcplog
            timeout     server                      2m
            tcp-request inspect-delay               5s
            tcp-request content accept              if { req_ssl_hello_type 1 }

            use_backend sydney-router-https         if { req_ssl_sni -m end -i apps.sydney.example.com }
            use_backend melbourne-router-https      if { req_ssl_sni -m end -i apps.melbourne.example.com }
            use_backend registry-https              if { req_ssl_sni -m end -i registry.example.com }

        backend         sydney-router-https
            balance     source
            server      compute1                     compute1.sydney.example.com:443     check
            server      compute2                     compute2.sydney.example.com:443     check
            server      compute3                     compute3.sydney.example.com:443     check

        backend         melbourne-router-https
            ....

#### 9.2.2. HANA backup pod cannot pull an image from an authenticated registry {#tshoot-hana-backup-image-pull}

If the configured container image registry requires authentication, HANA backup jobs might fail as shown in the following example:

    # oc get pods | grep backup-hana
    default-chq28a9-backup-hana-sjqph                                 0/2     ImagePullBackOff   0          15h
    default-hfiew1i-backup-hana-zv8g2                                 0/2     ImagePullBackOff   0          38h
    default-m21kt3d-backup-hana-zw7w4                                 0/2     ImagePullBackOff   0          39h
    default-w29xv3w-backup-hana-dzlvn                                 0/2     ImagePullBackOff   0          15h

    # oc describe pod default-hfiew1i-backup-hana-zv8g2 | tail -n 6
      Warning  Failed          12h (x5 over 12h)       kubelet            Error: ImagePullBackOff
      Warning  Failed          12h (x3 over 12h)       kubelet            Failed to pull image "sdi-registry.apps.shanghai.ocp.vslen/com.sap.datahub.linuxx86_64/hana:2010.22.0": rpc error: code = Unknown desc = Error reading manifest 2010.22.0 in sdi-registry.apps.shanghai.ocp.vslen/com.sap.datahub.linuxx86_64/hana: unauthorized: authentication required
      Warning  Failed          12h (x3 over 12h)       kubelet            Error: ErrImagePull
      Normal   Pulling         99m (x129 over 12h)     kubelet            Pulling image "sdi-registry.apps.shanghai.ocp.vslen/com.sap.datahub.linuxx86_64/hana:2010.22.0"
      Warning  Failed          49m (x3010 over 12h)    kubelet            Error: ImagePullBackOff
      Normal   BackOff         4m21s (x3212 over 12h)  kubelet            Back-off pulling image "sdi-registry.apps.shanghai.ocp.vslen/com.sap.datahub.linuxx86_64/hana:2010.22.0"

**Resolution**: There are two ways:

- The recommended approach is to update SDI Observer to version 0.1.9 or newer.

- A manual alternative fix is to execute the following:

    1. Determine the currently configured image pull secret:

            # oc get -n "${SDI_NAMESPACE:-sdi}" vc/vora -o jsonpath='{.spec.docker.imagePullSecret}{"\n"}'
            slp-docker-registry-pull-secret

    2. Link the secret with the default service account:

            # oc secret link --for=pull default slp-docker-registry-pull-secret

### 9.3. SDI Observer troubleshooting {#troubleshoot-sdi-observer}

#### 9.3.1. Build is failing due to a repository outage {#tshoot-observer-repo-outage}

If the build of SDI Observer or SDI Registry is failing with a similar error like the one below, the chosen Fedora repository mirror is probably temporarily down:

    # oc logs -n "${NAMESPACE:-sdi-observer}" -f bc/sdi-observer
    Extra Packages for Enterprise Linux Modular 8 - 448  B/s |  16 kB     00:36
    Failed to download metadata for repo 'epel-modular'
    Error: Failed to download metadata for repo 'epel-modular'
    subprocess exited with status 1
    subprocess exited with status 1
    error: build error: error building at STEP "RUN dnf install -y   https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm &&   dnf install -y parallel procps-ng bc git httpd-tools && dnf clean all -y": exit status 1

Please try to start the build again after a minute or two like this:

    # oc start-build NAMESPACE="${NAMESPACE:-sdi-observer}" -F bc/sdi-observer