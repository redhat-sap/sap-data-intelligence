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
	corev1 "k8s.io/api/core/v1"
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
	ReasonCRNotAvailable                  = "OperatorResourceNotAvailable"
	ReasonRouteNotAvailable               = "OperandRouteNotAvailable"
	ReasonOperandRouteFailed              = "OperandRouteFailed"
	ReasonSucceeded                       = "OperatorSucceeded"
	ReasonRouteManagementStateUnsupported = "RouteManagementStateUnsupported"
)

type StatusState string

const (
	SyncStatusState  StatusState = "SYNC"
	OkStatusState    StatusState = "OK"
	ErrorStatusState StatusState = "ERROR"
)

type RouteManagementState string

const (
	RouteManagedState                     RouteManagementState = "Managed"
	RouteUnmanagedState                   RouteManagementState = "Unmanaged"
	RouteRemovedStateRouteManagementState RouteManagementState = "Removed"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// ManagedRouteSpec allows to control route management for an SDI service.
type ManagedRouteSpec struct {
	// +kubebuilder:default="Managed"
	// +kubebuilder:validation:Enum=Managed;Unmanaged;Removed
	ManagementState string `json:"managementState,omitempty"`
}

const (
	ConditionRouteNotAdmitted = "NotAdmitted"
)

// ManagedRouteStatus informs about status of a managed route for an SDI service.
type ManagedRouteStatus struct {
	// Condition types:
	// - Exposed
	//     True when route is exposed and admitted.
	// - Degraded
	//     True when the desired state cannot be achieved (route is not admitted with Managed or route cannot
	//     be removed).
	// +optional
	// +patchMergeKey=type
	// +patchStrategy=merge
	Conditions []metav1.Condition `json:"conditions"`
}

const (
	// ConditionReasonNotFound indicates that no DataHub instance exists in the configured SDINamespace.
	ConditionReasonNotFound       = "NotFound"
	ConditionReasonAsExpected     = "AsExpected"
	ConditionReasonIngressBlocked = "IngressBlocked"
	ConditionReasonIngress        = "Ingress"
	// ConditionReasonAlreadyManaged indicates that another SDIObserver instance is currently managing the
	// target SDI Namespace.
	ConditionReasonAlreadyManaged = "AlreadyManaged"
	// ConditionReasonActive indicates that the managed SDIObserver instance is active in controlling the
	// target SDI Namespace.
	ConditionReasonActive = "Active"
	// ConditionReasonBackup indicates that the desired spec is not being worked on because the there is
	// another active instance managing the SDI namespace.
	ConditionReasonBackup = "Backup"
)

// SDIObserverSpec defines the desired state of SDIObserver
type SDIObserverSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	SDIVSystemRoute ManagedRouteSpec `json:"sdiVSystemRoute"`
	SLCBRoute       ManagedRouteSpec `json:"slcbRoute"`

	// TODO: add
	//nodeSelector map[string]string
}

// SDIObserverStatus defines the observed state of SDIObserver.
type SDIObserverStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
	// Used condition types:
	// - Degraded - a consolidated failure condition giving a hint on the failed dependency
	// - Progressing
	// - Ready - a consolidated condition being true when all the dependencies are fulfilled
	// - Backup - if true, there is another SDIObserver instance managing the target SDINamespace
	// +optional
	// +patchMergeKey=type
	// +patchStrategy=merge
	Conditions []metav1.Condition `json:"conditions"`
	// Reference to the DataHub resource found in the configured SDINamespace. It is left unset if the
	// resource does not exist or another instance is managing it.
	ManagedDataHubRef *corev1.ObjectReference `json:"managedDataHubs,omitempty"`
	// Status of the vsystem route. Conditions will be empty when not managed.
	VSystemRoute ManagedRouteStatus `json:"vsystemRoute,omitempty"`
	// Status of the slcb route. Conditions will be empty when not managed.
	SLCBRoute ManagedRouteStatus `json:"slcbRoute,omitempty"`
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
