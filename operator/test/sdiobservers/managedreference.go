package sdiobservers

import (
	"fmt"
	"reflect"
	"strings"

	onsitypes "github.com/onsi/gomega/types"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

func ReferenceDataHubByName(namespace, name string) onsitypes.GomegaMatcher {
	return &referenceMatcher{
		nmName: types.NamespacedName{Namespace: namespace, Name: name},
	}
}

func ReferenceDataHub(obj *unstructured.Unstructured) onsitypes.GomegaMatcher {
	if obj == nil {
		return &referenceMatcher{}
	}
	return &referenceMatcher{
		nmName:          client.ObjectKeyFromObject(obj),
		uid:             obj.GetUID(),
		resourceVersion: obj.GetResourceVersion(),
	}
}

func ReferenceDataHubByNamespacedName(nmName types.NamespacedName) onsitypes.GomegaMatcher {
	return &referenceMatcher{
		nmName: nmName,
	}
}

type referenceMatcher struct {
	nmName          types.NamespacedName
	uid             types.UID
	resourceVersion string
}

func getReference(actual interface{}) (*corev1.ObjectReference, error) {
	var ref *corev1.ObjectReference
	switch t := actual.(type) {
	case sdiv1alpha1.SDIObserver:
		ref = t.Status.ManagedDataHubRef
	case *sdiv1alpha1.SDIObserver:
		ref = t.Status.ManagedDataHubRef
	default:
		return nil, fmt.Errorf("referenceMatcher expects SDIObserver, not %T", t)
	}
	return ref, nil
}

func (m *referenceMatcher) Match(actual interface{}) (success bool, err error) {
	var ref *corev1.ObjectReference
	ref, err = getReference(actual)
	if err != nil {
		return
	}

	if reflect.DeepEqual(*m, referenceMatcher{}) && ref != nil {
		return false, nil
	}
	if reflect.DeepEqual(*m, referenceMatcher{}) && ref == nil {
		return true, nil
	}
	if !reflect.DeepEqual(*m, referenceMatcher{}) && ref == nil {
		return false, nil
	}
	if !reflect.DeepEqual(m.nmName, types.NamespacedName{Namespace: ref.Namespace, Name: ref.Name}) {
		return false, nil
	}
	if (len(m.uid) > 0 && m.uid != ref.UID) || len(ref.UID) == 0 {
		return false, nil
	}
	if (len(m.resourceVersion) > 0 && m.resourceVersion != ref.ResourceVersion) || len(ref.ResourceVersion) == 0 {
		return false, nil
	}
	if ref.APIVersion != "installers.datahub.sap.com/v1alpha1" {
		return false, nil
	}
	if ref.Kind != "DataHub" {
		return false, nil
	}
	return true, nil
}

func (m *referenceMatcher) FailureMessage(actual interface{}) (message string) {
	ref, err := getReference(actual)
	if err != nil {
		return err.Error()
	}

	if reflect.DeepEqual(*m, referenceMatcher{}) && ref != nil {
		return fmt.Sprintf("Expected ManagedDatahubRef to be nil, not: %#v", *ref)
	}
	if reflect.DeepEqual(*m, referenceMatcher{}) && ref == nil {
		panic("unexpected error")
	}
	if !reflect.DeepEqual(*m, referenceMatcher{}) && ref == nil {
		return "Expected ManagedDatahubRef not to be nil"
	}
	var errs []string
	{
		a := types.NamespacedName{Namespace: ref.Namespace, Name: ref.Name}
		if !reflect.DeepEqual(m.nmName, a) {
			errs = append(errs, fmt.Sprintf("to point at Namespace/Name=\"%s\", not \"%s\"", m.nmName.String(), a.String()))
		}
	}
	if len(m.uid) > 0 && m.uid != ref.UID {
		errs = append(errs, fmt.Sprintf("to point at UID=\"%s\", not \"%s\"", m.uid, ref.UID))
	} else if len(ref.UID) == 0 {
		errs = append(errs, "to have the UID set")
	}
	if len(m.resourceVersion) > 0 && m.resourceVersion != ref.ResourceVersion {
		errs = append(errs, fmt.Sprintf("to have the ResourceVersion=\"%s\", not \"%s\"", m.resourceVersion, ref.ResourceVersion))
	} else if len(ref.ResourceVersion) == 0 {
		errs = append(errs, "to have the ResourceVersion set")
	}
	if e := "installers.datahub.sap.com/v1alpha1"; ref.APIVersion != e {
		errs = append(errs, fmt.Sprintf("to have the APIVersion=\"%s\", not \"%s\"", e, ref.APIVersion))
	}
	if e := "DataHub"; ref.Kind != e {
		errs = append(errs, fmt.Sprintf("to have the Kind=\"%s\", not \"%s\"", e, ref.Kind))
	}
	if len(errs) == 0 {
		panic("unexpected error")
	}
	return fmt.Sprintf("Expected ManagedDatahubRef %s", strings.Join(errs, " AND "))
}

func (m *referenceMatcher) NegatedFailureMessage(actual interface{}) (message string) {
	ref, err := getReference(actual)
	if err != nil {
		return err.Error()
	}

	if reflect.DeepEqual(*m, referenceMatcher{}) && ref == nil {
		return "Expected ManagedDatahubRef not to be nil"
	}
	var errs []string
	{
		a := types.NamespacedName{Namespace: ref.Namespace, Name: ref.Name}
		if reflect.DeepEqual(m.nmName, a) && (len(m.uid) == 0 || m.uid == ref.UID) {
			errs = append(errs, fmt.Sprintf("to point at Namespace/Name=\"%s\"", m.nmName.String()))
		}
	}
	if len(m.uid) > 0 && m.uid == ref.UID {
		errs = append(errs, fmt.Sprintf("to point at UID=\"%s\"", m.uid))
	}
	if len(m.resourceVersion) > 0 && m.resourceVersion != ref.ResourceVersion {
		errs = append(errs, fmt.Sprintf("to have the ResourceVersion=\"%s\"", m.resourceVersion))
	}
	if len(errs) == 0 {
		panic("unexpected error")
	}
	if len(errs) == 1 {
		return fmt.Sprintf("Expected ManagedDatahubRef not %s", errs[0])
	}
	return fmt.Sprintf("Expected ManagedDatahubRef neither %s", strings.Join(errs, " NOR "))
}
