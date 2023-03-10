package adjuster

import (
	"context"
	"fmt"
	"github.com/go-logr/logr"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/controllers"
	corev1 "k8s.io/api/core/v1"
)

type Actioner interface {
	AdjustNodes(s *Adjuster, c context.Context) error
	AdjustNetwork(s *Adjuster, c context.Context) error
	AdjustStorage(s *Adjuster, c context.Context) error
	AdjustSDIConfig(s *Adjuster, c context.Context) error
}

type Adjuster struct {
	name               string
	Namespace          string
	Reconciler         *controllers.SDIObserverReconciler
	environmentVars    []corev1.EnvVar
	environmentSources []corev1.EnvFromSource
	resourceVars       []corev1.EnvVar
	logger             logr.Logger
}

// New creates a new Adjuster.
func New(
	name, namespace string,
	r *controllers.SDIObserverReconciler,
	logger logr.Logger,
) *Adjuster {
	return &Adjuster{
		name:       name,
		Namespace:  namespace,
		Reconciler: r,
	}
}

func (a *Adjuster) Adjust(c Actioner, ctx context.Context) error {
	if err := c.AdjustNodes(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of dependencies failed: %v", err)
	}
	if err := c.AdjustNetwork(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of network config failed: %v", err)
	}
	if err := c.AdjustStorage(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of storage failed: %v", err)
	}
	if err := c.AdjustSDIConfig(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of SDI config failed: %v", err)
	}
	return nil
}

func (a *Adjuster) Logger() logr.Logger {
	return a.logger
}
