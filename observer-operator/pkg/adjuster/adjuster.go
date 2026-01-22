package adjuster

import (
	"context"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	utilerrors "k8s.io/apimachinery/pkg/util/errors"
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
func New(name, namespace string, c client.Client, scheme *runtime.Scheme, logger logr.Logger) *Adjuster {
	return &Adjuster{
		Name:      name,
		Namespace: namespace,
		Client:    c,
		Scheme:    scheme,
		logger:    logger,
	}
}

// Adjust performs a series of adjustments using the provided Actioner.
// It continues processing all adjustments even if some fail, collecting errors.
// NotFound errors are logged and skipped (component not yet available).
// Other errors are aggregated and returned at the end.
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

	var errs []error
	for _, adjustment := range adjustments {
		if err := adjustment.action(); err != nil {
			if isNotFoundError(err) {
				a.logger.Info("Component not found, skipping adjustment", "adjustment", adjustment.name, "error", err.Error())
				continue
			}
			a.logger.Error(err, "Adjustment failed", "adjustment", adjustment.name)
			errs = append(errs, err)
		}
	}

	return utilerrors.NewAggregate(errs)
}

// isNotFoundError checks if an error (or all errors in an aggregate) are NotFound errors.
// This handles both single errors and aggregate errors from utilerrors.NewAggregate.
func isNotFoundError(err error) bool {
	if err == nil {
		return false
	}

	// Check if it's a single NotFound error
	if errors.IsNotFound(err) {
		return true
	}

	// Check if it's an aggregate where ALL errors are NotFound
	if agg, ok := err.(utilerrors.Aggregate); ok {
		for _, e := range agg.Errors() {
			if !isNotFoundError(e) {
				return false
			}
		}
		return len(agg.Errors()) > 0
	}

	return false
}

// Logger returns the logger instance associated with the Adjuster.
func (a *Adjuster) Logger() logr.Logger {
	return a.logger
}
