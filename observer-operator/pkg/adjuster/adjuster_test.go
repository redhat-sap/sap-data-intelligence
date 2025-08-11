package adjuster

import (
	"context"
	"testing"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// MockActioner implements the Actioner interface for testing
type MockActioner struct {
	AdjustNodesFunc       func(a *Adjuster, ctx context.Context) error
	AdjustSDINetworkFunc  func(a *Adjuster, ctx context.Context) error
	AdjustSLCBNetworkFunc func(a *Adjuster, ctx context.Context) error
	AdjustStorageFunc     func(a *Adjuster, ctx context.Context) error
	AdjustSDIConfigFunc   func(a *Adjuster, ctx context.Context) error
}

func (m *MockActioner) AdjustNodes(a *Adjuster, ctx context.Context) error {
	if m.AdjustNodesFunc != nil {
		return m.AdjustNodesFunc(a, ctx)
	}
	return nil
}

func (m *MockActioner) AdjustSDINetwork(a *Adjuster, ctx context.Context) error {
	if m.AdjustSDINetworkFunc != nil {
		return m.AdjustSDINetworkFunc(a, ctx)
	}
	return nil
}

func (m *MockActioner) AdjustSLCBNetwork(a *Adjuster, ctx context.Context) error {
	if m.AdjustSLCBNetworkFunc != nil {
		return m.AdjustSLCBNetworkFunc(a, ctx)
	}
	return nil
}

func (m *MockActioner) AdjustStorage(a *Adjuster, ctx context.Context) error {
	if m.AdjustStorageFunc != nil {
		return m.AdjustStorageFunc(a, ctx)
	}
	return nil
}

func (m *MockActioner) AdjustSDIConfig(a *Adjuster, ctx context.Context) error {
	if m.AdjustSDIConfigFunc != nil {
		return m.AdjustSDIConfigFunc(a, ctx)
	}
	return nil
}

func TestNew(t *testing.T) {
	scheme := runtime.NewScheme()
	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	logger := logr.Discard()

	adjuster := New("test-name", "test-namespace", client, scheme, logger)

	if adjuster.Name != "test-name" {
		t.Errorf("Expected name 'test-name', got '%s'", adjuster.Name)
	}
	if adjuster.Namespace != "test-namespace" {
		t.Errorf("Expected namespace 'test-namespace', got '%s'", adjuster.Namespace)
	}
	if adjuster.Client != client {
		t.Error("Client not set correctly")
	}
	if adjuster.Scheme != scheme {
		t.Error("Scheme not set correctly")
	}
}

func TestAdjuster_Adjust_Success(t *testing.T) {
	scheme := runtime.NewScheme()
	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	logger := logr.Discard()

	adjuster := New("test-name", "test-namespace", client, scheme, logger)
	mockActioner := &MockActioner{}

	ctx := context.Background()
	err := adjuster.Adjust(mockActioner, ctx)

	if err != nil {
		t.Errorf("Expected no error, got %v", err)
	}
}

func TestAdjuster_Adjust_ErrorPropagation(t *testing.T) {
	scheme := runtime.NewScheme()
	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	logger := logr.Discard()

	adjuster := New("test-name", "test-namespace", client, scheme, logger)

	expectedError := "test error"
	mockActioner := &MockActioner{
		AdjustNodesFunc: func(_ *Adjuster, _ context.Context) error {
			return nil
		},
		AdjustSLCBNetworkFunc: func(_ *Adjuster, _ context.Context) error {
			return &MockError{message: expectedError}
		},
	}

	ctx := context.Background()
	err := adjuster.Adjust(mockActioner, ctx)

	if err == nil {
		t.Error("Expected error, got nil")
	}
	if err.Error() != expectedError {
		t.Errorf("Expected error '%s', got '%v'", expectedError, err)
	}
}

func TestAdjuster_Logger(t *testing.T) {
	scheme := runtime.NewScheme()
	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	logger := logr.Discard()

	adjuster := New("test-name", "test-namespace", client, scheme, logger)

	returnedLogger := adjuster.Logger()
	if returnedLogger != logger {
		t.Error("Logger not returned correctly")
	}
}

// MockError implements error interface for testing
type MockError struct {
	message string
}

func (e *MockError) Error() string {
	return e.message
}
