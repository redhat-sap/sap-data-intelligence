package adjuster

import (
	"context"
	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type Actioner interface {
	AdjustNodes(a *Adjuster, ctx context.Context) error
	AdjustSDINetwork(a *Adjuster, ctx context.Context) error
	AdjustSLCBNetwork(a *Adjuster, ctx context.Context) error
	AdjustStorage(a *Adjuster, ctx context.Context) error
	AdjustSDIConfig(a *Adjuster, ctx context.Context) error
}

type Adjuster struct {
	Name      string
	Namespace string
	Client    client.Client
	Scheme    *runtime.Scheme
	logger    logr.Logger
}

// New creates a new Adjuster with the provided parameters.
func New(name, namespace string, client client.Client, scheme *runtime.Scheme, logger logr.Logger) *Adjuster {
	return &Adjuster{
		Name:      name,
		Namespace: namespace,
		Client:    client,
		Scheme:    scheme,
		logger:    logger,
	}
}

// Adjust performs a series of adjustments using the provided Actioner.
func (a *Adjuster) Adjust(ac Actioner, ctx context.Context) error {
	// List of adjustment functions with their corresponding log messages
	adjustments := []struct {
		name   string
		action func() error
	}{
		{"nodes", func() error { return ac.AdjustNodes(a, ctx) }},
		{"SLCB network", func() error { return ac.AdjustSLCBNetwork(a, ctx) }},
		{"storage", func() error { return ac.AdjustStorage(a, ctx) }},
		{"SDI config", func() error { return ac.AdjustSDIConfig(a, ctx) }},
		{"SDI network", func() error { return ac.AdjustSDINetwork(a, ctx) }},
	}

	for _, adjustment := range adjustments {
		if err := adjustment.action(); err != nil {
			return err
		}
	}

	return nil
}

// Logger returns the logger instance associated with the Adjuster.
func (a *Adjuster) Logger() logr.Logger {
	return a.logger
}
