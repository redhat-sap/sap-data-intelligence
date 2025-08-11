package adjuster

import (
	"context"
	"fmt"
	"strings"

	routev1 "github.com/openshift/api/route/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/observer-operator/api/v1alpha1"
	"github.com/redhat-sap/sap-data-intelligence/observer-operator/assets"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	// These are configuration file names, not actual credentials
	vsystemCaBundleSecretName = "ca-bundle.pem" // #nosec G101
	vsystemCaBundleSecretKey  = "ca-bundle.pem" // #nosec G101
)

// AdjustRoute manages the route based on its management state.
func (a *Adjuster) AdjustRoute(ns, name string, managementState sdiv1alpha1.RouteManagementState, routeFile, svcName string, obs *sdiv1alpha1.SDIObserver, ctx context.Context, handleCA bool) error {
	route := &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: ns,
		},
	}

	switch managementState {
	case sdiv1alpha1.RouteManagementStateManaged:
		return a.handleManagedRoute(ns, name, routeFile, svcName, route, obs, ctx, handleCA)
	case sdiv1alpha1.RouteManagementStateUnmanaged:
		a.logger.Info("Route is unmanaged; no action needed.")
		return nil
	case sdiv1alpha1.RouteManagementStateRemoved:
		return a.handleRemovedRoute(ns, name, route, obs, ctx)
	default:
		return fmt.Errorf("unsupported Route Management State: %s", managementState)
	}
}

func (a *Adjuster) handleManagedRoute(ns, name, routeFile, svcName string, route *routev1.Route, obs *sdiv1alpha1.SDIObserver, ctx context.Context, handleCA bool) error {
	create := false
	err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route)

	switch {
	case err != nil && errors.IsNotFound(err):
		create = true
		route = assets.GetRouteFromFile(routeFile)
		route.Namespace = ns
		route.Name = name
		if handleCA {
			svc := &corev1.Service{
				ObjectMeta: metav1.ObjectMeta{
					Name:      svcName,
					Namespace: ns,
				},
			}

			if err := a.Client.Get(ctx, types.NamespacedName{Namespace: ns, Name: svcName}, svc); err != nil && !errors.IsNotFound(err) {
				return err
			}

			caBundleSecret := &corev1.Secret{}
			if err := a.Client.Get(ctx, types.NamespacedName{Namespace: ns, Name: vsystemCaBundleSecretName}, caBundleSecret); err != nil {
				return err
			}

			caBundle, err := getCertFromCaBundleSecret(caBundleSecret)
			if err != nil {
				return err
			}
			route.Spec.TLS.DestinationCACertificate = caBundle
		}
	case err != nil:
		return err
	case handleCA:
		caBundleSecret := &corev1.Secret{}
		if err := a.Client.Get(ctx, types.NamespacedName{Namespace: ns, Name: vsystemCaBundleSecretName}, caBundleSecret); err != nil {
			return err
		}

		caBundle, err := getCertFromCaBundleSecret(caBundleSecret)
		if err != nil {
			return err
		}
		if route.Spec.TLS.DestinationCACertificate == caBundle {
			a.logger.Info(fmt.Sprintf("Route %s destination CA certificate is unchanged", name))
			return nil
		}
		route.Spec.TLS.DestinationCACertificate = caBundle
	}

	if create {
		err = a.Client.Create(ctx, route)
	} else {
		if name == "sap-slcbridge" && route.Spec.To.Name == "slcbridgebase-service" {
			a.logger.Info("SLCB route configuration is already correct. No action needed.")
			return nil
		}
		err = a.Client.Update(ctx, route)
	}

	if err != nil {
		return err
	}

	return nil
}

// handleRemovedRoute handles routes that are in a removed state.
func (a *Adjuster) handleRemovedRoute(ns, name string, route *routev1.Route, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	if err := a.Client.Get(ctx, client.ObjectKey{Name: name, Namespace: ns}, route); err != nil && errors.IsNotFound(err) {
		a.logger.Info(fmt.Sprintf("Operand route does not exist: %s", err.Error()))
		return nil
	} else if err != nil {
		return err
	}

	if err := a.Client.Delete(ctx, route); err != nil {
		return err
	}

	return nil
}

// AdjustSDIVsystemRoute adjusts the VSystem route.
func (a *Adjuster) AdjustSDIVsystemRoute(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	return a.AdjustRoute(ns, "vsystem", obs.Spec.SDIVSystemRoute.ManagementState, "manifests/route-management/route-vsystem.yaml", "vsystem-service", obs, ctx, true)
}

// AdjustSLCBRoute adjusts the SLCB route.
func (a *Adjuster) AdjustSLCBRoute(ns string, obs *sdiv1alpha1.SDIObserver, ctx context.Context) error {
	return a.AdjustRoute(ns, "sap-slcbridge", obs.Spec.SLCBRoute.ManagementState, "manifests/route-management/route-sap-slcbridge.yaml", "slcb-service", obs, ctx, false)
}

func getCertFromCaBundleSecret(secret *corev1.Secret) (string, error) {
	value, ok := secret.Data[vsystemCaBundleSecretKey]
	if !ok {
		return "", fmt.Errorf("failed to find key \"%s\" in \"%s\" secret", vsystemCaBundleSecretKey, secret.ObjectMeta.Name)
	}
	return strings.TrimSpace(string(value)), nil
}
