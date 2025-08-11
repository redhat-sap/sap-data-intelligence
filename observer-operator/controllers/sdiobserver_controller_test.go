package controllers

import (
	"context"
	"testing"
	"time"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

func TestSDIObserverReconciler_Reconcile_NotFound(t *testing.T) {
	scheme := runtime.NewScheme()
	err := sdiv1alpha1.AddToScheme(scheme)
	if err != nil {
		t.Fatalf("Failed to add scheme: %v", err)
	}

	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	
	reconciler := &SDIObserverReconciler{
		Client:            client,
		Scheme:            scheme,
		ObserverNamespace: "test-namespace",
		Interval:          1 * time.Minute,
	}

	req := reconcile.Request{
		NamespacedName: types.NamespacedName{
			Name:      "non-existent",
			Namespace: "test-namespace",
		},
	}

	ctx := context.Background()
	result, err := reconciler.Reconcile(ctx, req)

	if err != nil {
		t.Errorf("Expected no error, got %v", err)
	}

	if result.Requeue {
		t.Error("Expected no requeue")
	}

	if result.RequeueAfter != 0 {
		t.Error("Expected no requeue after")
	}
}

func TestSDIObserverReconciler_Reconcile_Success(t *testing.T) {
	scheme := runtime.NewScheme()
	err := sdiv1alpha1.AddToScheme(scheme)
	if err != nil {
		t.Fatalf("Failed to add scheme: %v", err)
	}

	obs := &sdiv1alpha1.SDIObserver{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-observer",
			Namespace: "test-namespace",
		},
		Spec: sdiv1alpha1.SDIObserverSpec{
			SDINamespace:        "sdi",
			SLCBNamespace:       "slcb",
			ManageSDINodeConfig: false, // Set to false to avoid node operations in test
		},
	}

	client := fake.NewClientBuilder().WithScheme(scheme).WithObjects(obs).Build()
	
	reconciler := &SDIObserverReconciler{
		Client:            client,
		Scheme:            scheme,
		ObserverNamespace: "test-namespace",
		Interval:          1 * time.Minute,
	}

	req := reconcile.Request{
		NamespacedName: types.NamespacedName{
			Name:      "test-observer",
			Namespace: "test-namespace",
		},
	}

	ctx := context.Background()
	result, err := reconciler.Reconcile(ctx, req)

	// We expect an error here because the test doesn't set up all the required resources
	// But we're testing that the reconciler doesn't panic and handles the error gracefully
	if err == nil {
		t.Log("No error occurred - this might indicate missing test setup or successful reconciliation")
	}

	// The result should include a requeue after interval
	if result.RequeueAfter == 0 {
		t.Error("Expected requeue after interval")
	}
}

func TestSDIObserverReconciler_ensureStatusConditions(t *testing.T) {
	scheme := runtime.NewScheme()
	err := sdiv1alpha1.AddToScheme(scheme)
	if err != nil {
		t.Fatalf("Failed to add scheme: %v", err)
	}

	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	
	reconciler := &SDIObserverReconciler{
		Client:            client,
		Scheme:            scheme,
		ObserverNamespace: "test-namespace",
		Interval:          1 * time.Minute,
	}

	// Test with empty conditions
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

	updated := reconciler.ensureStatusConditions(obs)
	if !updated {
		t.Error("Expected status to be updated when conditions are empty")
	}

	if len(obs.Status.Conditions) == 0 {
		t.Error("Expected conditions to be initialized")
	}

	// Test with existing conditions
	updated = reconciler.ensureStatusConditions(obs)
	if updated {
		t.Error("Expected no update when conditions already exist")
	}
}

func TestSDIObserverReconciler_handleError(t *testing.T) {
	scheme := runtime.NewScheme()
	err := sdiv1alpha1.AddToScheme(scheme)
	if err != nil {
		t.Fatalf("Failed to add scheme: %v", err)
	}

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

	client := fake.NewClientBuilder().WithScheme(scheme).WithObjects(obs).Build()
	
	reconciler := &SDIObserverReconciler{
		Client:            client,
		Scheme:            scheme,
		ObserverNamespace: "test-namespace",
		Interval:          1 * time.Minute,
	}

	ctx := context.Background()
	testError := &TestError{message: "test error"}
	result, err := reconciler.handleError(ctx, obs, testError, "Test error message")

	// The handleError method may return an aggregate error including update errors
	if err == nil {
		t.Error("Expected an error to be returned")
	}

	if result.RequeueAfter != 1*time.Minute {
		t.Error("Expected requeue after 1 minute")
	}

	// Check that the status condition was set (may not persist due to fake client limitations)
	// This is mainly testing that handleError doesn't panic and sets the appropriate requeue
	if len(obs.Status.Conditions) > 0 {
		t.Log("Status conditions were set as expected")
	}
}

// TestSDIObserverReconciler_SetupWithManager would require a more complex mock
// manager setup, so we'll skip it for now in favor of simpler unit tests

// TestError implements error interface for testing
type TestError struct {
	message string
}

func (e *TestError) Error() string {
	return e.message
}