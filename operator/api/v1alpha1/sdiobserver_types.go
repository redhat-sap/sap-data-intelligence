/*
Copyright 2022.

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
	RouteManagementStateManaged   = "Managed"
	RouteManagementStateUnmanaged = "Unmanaged"
	RouteManagementStateRemoved   = "Removed"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

type SdiObserverSpecRoute struct {
	// +kubebuilder:default="Managed"
	// +kubebuilder:validation:Enum=Managed;Unmanaged;Removed
	ManagementState string `json:"managementState,omitempty"`
	// +kubebuilder:validation:Optional
	// +kubebuilder:validation:Pattern="[[:alnum:]]+(-[[:alnum:]]+)*(\\.[[:alnum:]]+(-[[:alnum:]]+)*)*"
	Hostname string `json:"hostname,omitempty"`
}

// SdiObserverSpec defines the desired state of SdiObserver
type SdiObserverSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// Foo is an example field of SdiObserver. Edit sdiobserver_types.go to remove/update
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=2
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern="[[:alnum:]]+(-[[:alnum:]]+)*"
	SdiNamespace string `json:"sdiNamespace,omitempty"`
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=2
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern="[[:alnum:]]+(-[[:alnum:]]+)*"
	SlcbNamespace string `json:"slcbNamespace,omitempty"`

	VsystemRoute SdiObserverSpecRoute `json:"vsystemRoute"`
	SlcbRoute    SdiObserverSpecRoute `json:"slcbRoute"`

	// TODO: add
	//nodeSelector map[string]string
}

// SdiObserverStatus defines the observed state of SdiObserver
type SdiObserverStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// SdiObserver is the Schema for the sdiobservers API
type SdiObserver struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   SdiObserverSpec   `json:"spec,omitempty"`
	Status SdiObserverStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// SdiObserverList contains a list of SdiObserver
type SdiObserverList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []SdiObserver `json:"items"`
}

func init() {
	SchemeBuilder.Register(&SdiObserver{}, &SdiObserverList{})
}
