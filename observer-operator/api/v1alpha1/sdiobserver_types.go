/*
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
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	// RouteManagementStateManaged instructs the observer to manage the route for the corresponding k8s
	// service. The route will be created if the service exists and be kept up to date for any changes to the
	// service or the associated secret with CA certificate. If the service does not exist, the route is
	// deleted.
	RouteManagementStateManaged = "Managed"
	// RouteManagementStateUnmanaged instructs the observer to ignore particular k8s service and its route.
	RouteManagementStateUnmanaged = "Unmanaged"
	// RouteManagementStateRemoved instructs the observer to keep the route deleted.
	RouteManagementStateRemoved = "Removed"
)

const (
	ConditionTypeReconcile   = "Reconcile"
	ConditionTypeReady       = "Ready"
	ConditionTypeDegraded    = "Degraded"
	ConditionTypeProgressing = "Progressing"
)

const (
	ReasonCRNotAvailable                  = "OperatorResourceNotAvailable"
	ReasonResourceNotAvailable            = "OperandResourceNotAvailable"
	ReasonOperandResourceFailed           = "OperandResourceFailed"
	ReasonSucceeded                       = "OperatorSucceeded"
	ReasonRouteManagementStateUnsupported = "RouteManagementStateUnsupported"
	ReasonFailed                          = "OperatorFailed"
)

type RouteManagementState string

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// ManagedRouteSpec allows to control route management for an SDI service.
type ManagedRouteSpec struct {
	// +kubebuilder:default="Managed"
	// +kubebuilder:validation:Enum=Managed;Unmanaged;Removed
	ManagementState RouteManagementState `json:"managementState,omitempty"`
}

// ManagedRouteStatus informs about status of a managed route for an SDI service.
type ManagedRouteStatus struct {
	Conditions []metav1.Condition `json:"conditions"`
}

// SDIConfigStatus informs about status of SDI patching.
type SDIConfigStatus struct {
	Conditions []metav1.Condition `json:"conditions"`
}

// SDINodeConfigStatus informs about status of SDI node configuration.
type SDINodeConfigStatus struct {
	Conditions []metav1.Condition `json:"conditions"`
}

// SDIObserverSpec defines the desired state of SDIObserver
type SDIObserverSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=2
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern="[[:alnum:]]+(-[[:alnum:]]+)*"
	// SLCBNamespace is the namespace in which the SAP Data Intelligence is running
	SDINamespace string `json:"sdiNamespace"`

	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=2
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern="[[:alnum:]]+(-[[:alnum:]]+)*"
	// SLCBNamespace is the namespace in which the SAP SLC Bridge is running
	SLCBNamespace string `json:"slcbNamespace"`

	SDIVSystemRoute ManagedRouteSpec `json:"sdiVSystemRoute"`
	SLCBRoute       ManagedRouteSpec `json:"slcbRoute"`

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=true
	// ManageSDINodeConfig defines whether SAP DI node configuration (load kernel modules, change container PID limits) will be managed by Operator
	ManageSDINodeConfig bool `json:"manageSDINodeConfig"`

	// +kubebuilder:validation:Optional
	// +kubebuilder:default:="node-role.kubernetes.io/sdi="
	// SDINodeLabel should be set to the corresponding SAP DI node label. It will be used for annotating the namespaces of SAP DI service so that the Pods will be running on the labeled SAP DI node
	SDINodeLabel string `json:"SDINodeLabel"`
}

// SDIObserverStatus defines the observed state of SDIObserver.
type SDIObserverStatus struct {
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// Status of the vsystem route.
	VSystemRouteStatus ManagedRouteStatus `json:"vsystemRouteStatus,omitempty"`

	// Status of the slcb route.
	SLCBRouteStatus ManagedRouteStatus `json:"slcbRouteStatus,omitempty"`

	// Status of the SDI config.
	SDIConfigStatus SDIConfigStatus `json:"sdiConfigStatus,omitempty"`

	// Status of the SDI node config.
	SDINodeConfigStatus SDINodeConfigStatus `json:"sdiNodeConfigStatus,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// SDIObserver is the Schema for the sdiobservers API
type SDIObserver struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   SDIObserverSpec   `json:"spec,omitempty"`
	Status SDIObserverStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// SDIObserverList contains a list of SDIObserver
type SDIObserverList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []SDIObserver `json:"items"`
}

func init() {
	SchemeBuilder.Register(&SDIObserver{}, &SDIObserverList{})
}
