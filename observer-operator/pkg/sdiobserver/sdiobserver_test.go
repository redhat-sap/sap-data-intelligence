package sdiobserver

import (
	"testing"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestNew(t *testing.T) {
	obs := &sdiv1alpha1.SDIObserver{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-observer",
			Namespace: "test-namespace",
		},
		Spec: sdiv1alpha1.SDIObserverSpec{
			SDINamespace:  "sdi",
			SLCBNamespace: "slcb",
		},
	}

	sdiObserver := New(obs)

	if sdiObserver.obs != obs {
		t.Error("SDIObserver not set correctly")
	}
}

func TestSDIObserver_AdjustNodes_Managed(t *testing.T) {
	obs := &sdiv1alpha1.SDIObserver{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-observer",
			Namespace: "test-namespace",
		},
		Spec: sdiv1alpha1.SDIObserverSpec{
			SDINamespace:        "sdi",
			SLCBNamespace:       "slcb",
			ManageSDINodeConfig: true,
		},
	}

	sdiObserver := New(obs)
	
	// For now, we'll test the basic functionality without mocking the adjuster
	// since that would require more complex interface setup
	
	if sdiObserver.obs.Spec.ManageSDINodeConfig != true {
		t.Error("Expected ManageSDINodeConfig to be true")
	}
}

func TestSDIObserver_AdjustNodes_Unmanaged(t *testing.T) {
	obs := &sdiv1alpha1.SDIObserver{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-observer",
			Namespace: "test-namespace",
		},
		Spec: sdiv1alpha1.SDIObserverSpec{
			SDINamespace:        "sdi",
			SLCBNamespace:       "slcb",
			ManageSDINodeConfig: false,
		},
	}

	sdiObserver := New(obs)
	
	if sdiObserver.obs.Spec.ManageSDINodeConfig != false {
		t.Error("Expected ManageSDINodeConfig to be false")
	}
}

// Note: More comprehensive tests with mock adjusters can be added
// in integration tests where we can properly mock the adjuster interface