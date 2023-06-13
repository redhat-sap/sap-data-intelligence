package adjuster

import (
	"context"
	"fmt"
	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type Actioner interface {
	AdjustNodes(s *Adjuster, c context.Context) error
	AdjustSDINetwork(s *Adjuster, c context.Context) error
	AdjustSLCBNetwork(s *Adjuster, c context.Context) error
	AdjustStorage(s *Adjuster, c context.Context) error
	AdjustSDIConfig(s *Adjuster, c context.Context) error
}

type Adjuster struct {
	name      string
	Namespace string
	Client    client.Client
	Scheme    *runtime.Scheme
	logger    logr.Logger
}

// New creates a new Adjuster.
func New(
	n string,
	ns string,
	c client.Client,
	s *runtime.Scheme,
	l logr.Logger,
) *Adjuster {
	return &Adjuster{
		name:      n,
		Namespace: ns,
		Client:    c,
		Scheme:    s,
		logger:    l,
	}
}

func (a *Adjuster) Adjust(ac Actioner, ctx context.Context) error {
	if err := ac.AdjustNodes(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of nodes failed: %v", err)
	}
	if err := ac.AdjustSLCBNetwork(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of network config failed: %v", err)
	}
	if err := ac.AdjustStorage(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of storage failed: %v", err)
	}
	if err := ac.AdjustSDIConfig(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of SDI config failed: %v", err)
	}
	if err := ac.AdjustSDINetwork(a, ctx); err != nil {
		return fmt.Errorf("Adjustment of network config failed: %v", err)
	}
	return nil
}

func (a *Adjuster) Logger() logr.Logger {
	return a.logger
}
