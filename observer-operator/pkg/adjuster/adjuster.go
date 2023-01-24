package adjuster

import (
	"context"
	"fmt"
	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type Actioner interface {
	AdjustNodes(s *Adjuster) error
	AdjustNetwork(s *Adjuster) error
	AdjustStorage(s *Adjuster) error
	AdjustSDIConfig(s *Adjuster) error
	AdjustedStatus() client.Object
}

type Adjuster struct {
	name               string
	namespace          string
	client             client.Client
	scheme             *runtime.Scheme
	ownerReference     metav1.OwnerReference
	environmentVars    []corev1.EnvVar
	environmentSources []corev1.EnvFromSource
	resourceVars       []corev1.EnvVar
	logger             logr.Logger
}

// New creates a new Adjuster.
func New(
	name, namespace string,
	client client.Client,
	scheme *runtime.Scheme,
	ownerReference metav1.OwnerReference,
	logger logr.Logger,
) *Adjuster {
	return &Adjuster{
		name:           name,
		namespace:      namespace,
		client:         client,
		scheme:         scheme,
		ownerReference: ownerReference,
		logger:         logger,
	}
}

func (a *Adjuster) Adjust(ctx context.Context, c Actioner) error {
	if err := c.AdjustNodes(a); err != nil {
		return fmt.Errorf("Adjustment of dependencies failed: %v", err)
	}
	if err := c.AdjustNetwork(a); err != nil {
		return fmt.Errorf("Adjustment of network config failed: %v", err)
	}
	if err := c.AdjustStorage(a); err != nil {
		return fmt.Errorf("Adjustment of storage failed: %v", err)
	}
	if err := c.AdjustSDIConfig(a); err != nil {
		return fmt.Errorf("Adjustment of SDI config failed: %v", err)
	}
	a.UpdateStatus(c.AdjustedStatus())
	return nil
}

func (a *Adjuster) Logger() logr.Logger {
	return a.logger
}

func (a *Adjuster) UpdateStatus(obj client.Object) {
	err := a.client.Status().Update(context.Background(), obj)
	if err != nil {
		a.logger.V(1).Info(err.Error())
	}
}
