package v1alpha1

import (
	"encoding/json"
	"os"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// +k8s:deepcopy-gen=v1alpha1

type DataHubSpec struct {
}

//+kubebuilder:object:root=true
type DataHub struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              DataHubSpec `json:"spec,omitempty"`
}

//+kubebuilder:object:root=true
type DataHubList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []DataHub `json:"items"`
}

/*
func AddToScheme(s *runtime.Scheme) error {
    schemeBuilder := &scheme.Builder{
		GroupVersion: schema.GroupVersion{Group: "installers.datahub.sap.com",
		Version: "v1alpha1"},
	}
	//TODO
    //schemeBuilder.Register(&DataHub{}, &DataHubList{})
    return schemeBuilder.AddToScheme(s)
}
*/

func DataHubToUnstructured(dh *DataHub) (*unstructured.Unstructured, error) {
	encoded, err := json.Marshal(dh)
	if err != nil {
		return nil, err
	}
	res := &unstructured.Unstructured{}
	err = res.UnmarshalJSON(encoded)
	if err != nil {
		return nil, err
	}
	return res, nil
}

func GetSampleDH(namespace string) *unstructured.Unstructured {
	res, err := DataHubToUnstructured(&DataHub{
		TypeMeta: metav1.TypeMeta{
			Kind: "DataHub",
			APIVersion: schema.GroupVersion{
				Group:   "installers.datahub.sap.com",
				Version: "v1alpha1",
			}.String(),
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:      "default",
			Namespace: namespace,
		},
	})
	if err != nil {
		log.Log.Error(err, "failed to convert DataHub to Unstructured")
		os.Exit(1)
	}
	return res
}
