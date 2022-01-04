package managed_dh

import (
	"context"
	"fmt"
	"reflect"
	"regexp"
	"strings"

	"github.com/google/go-cmp/cmp"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/util/retry"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	routev1 "github.com/openshift/api/route/v1"
	//csroute "github.com/openshift/client-go/route/clientset/versioned/typed/route/v1"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

const (
	vsystemCaBundleSecretName = "ca-bundle.pem"
	vsystemCaBundleSecretKey  = "ca-bundle.pem"
	vsystemPortNumber         = 8797

	routeAnnotationTimeoutKey   = "haproxy.router.openshift.io/timeout"
	routeAnnotationTimeoutValue = "2m"

	// Annotations for owned resources in other namespaces.
	// expected value: {metadata.namespace}/{metadata.name}
	opSdkPrimaryResourceAnnotationKey = "operator-sdk/primary-resource"
	// expected value: {kind}.{group}
	opSdkPrimaryResourceTypeAnnotationKey = "operator-sdk/primary-resource-type"
)

func manageVsystemRoute(
	ctx context.Context,
	scheme *runtime.Scheme,
	client client.Client,
	owner *sdiv1alpha1.SdiObserver,
	rc *sdiv1alpha1.SdiObserverSpecRoute,
	namespace string,
) error {
	logger := log.FromContext(ctx)
	if regexp.MustCompile("^(\\s*|(?i)Unmanaged)$").MatchString(rc.ManagementState) {
		logger.V(2).Info("vsystem route is not managed")
		// TODO: need to update at least the owner's status
		return nil
	}

	svcKey := types.NamespacedName{
		Namespace: namespace,
		Name:      "vsystem",
	}

	/*
		corecs := c8s.NewForConfigOrDie(cfg).CoreV1()
		svcs := corecs.Services(namespace)
	*/
	svc := &corev1.Service{}
	svcGetErr := client.Get(ctx, types.NamespacedName{
		Namespace: namespace,
		Name:      "vsystem",
	}, svc)
	if svcGetErr != nil && !errors.IsNotFound(svcGetErr) {
		logger.Error(svcGetErr, "failed to get vsystem service")
		return svcGetErr
	}

	err := retry.RetryOnConflict(retry.DefaultRetry, func() error {
		route := &routev1.Route{}
		routeGetErr := client.Get(ctx, svcKey, route)
		if routeGetErr != nil && !errors.IsNotFound(routeGetErr) {
			logger.Error(routeGetErr, "failed to get vsystem route")
			return routeGetErr
		}

		if regexp.MustCompile("^(?i)removed?$").MatchString(rc.ManagementState) || errors.IsNotFound(svcGetErr) {
			if errors.IsNotFound(routeGetErr) {
				logger.Info("vsystem route already removed, nothing to do")
				return nil
			}
			logger.Info("deleting vsystem route")
			if err := client.Delete(ctx, route); err != nil {
				if !errors.IsNotFound(err) {
					logger.Error(err, "failed to delete vsystem route")
				}
			}
			return nil
		}

		caBundleSecret := &corev1.Secret{}
		err := client.Get(ctx, types.NamespacedName{
			Namespace: namespace,
			Name:      vsystemCaBundleSecretName,
		}, caBundleSecret)
		if err != nil {
			logger.Error(err, "failed to get vsystem/vora ca-bundle.pem secret")
			return err
		}
		caBundle, err := getCertFromCaBundleSecret(caBundleSecret)
		if err != nil {
			return err
		}

		newRoute := routev1.Route{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: namespace,
				Name:      svc.ObjectMeta.Name,
				Annotations: map[string]string{
					routeAnnotationTimeoutKey: routeAnnotationTimeoutValue,
					// cannot use ownerReferences for resources in other namespaces; this is a substitute
					opSdkPrimaryResourceAnnotationKey: fmt.Sprintf("%s/%s", owner.ObjectMeta.Namespace, owner.ObjectMeta.Name),
					opSdkPrimaryResourceTypeAnnotationKey: schema.GroupKind{
						Group: sdiv1alpha1.GroupVersion.Group,
						Kind:  "SdiObserver",
					}.String(),
				},
				Labels: getRouteLabelsForVsystemService(svc),
			},
			Spec: routev1.RouteSpec{
				To: routev1.RouteTargetReference{
					Kind: "Service",
					Name: "vsystem",
				},
				Port: getRoutePortForVsystemService(svc),
				TLS: &routev1.TLSConfig{
					Termination:                   routev1.TLSTerminationReencrypt,
					DestinationCACertificate:      caBundle,
					InsecureEdgeTerminationPolicy: routev1.InsecureEdgeTerminationPolicyRedirect,
				},
			},
		}
		if len(rc.Hostname) > 0 {
			newRoute.Spec.Host = rc.Hostname
		}

		if routeGetErr == nil {
			changed, updatedFields := updateRoute(route, &newRoute)
			if !changed {
				logger.Info("manageVsystemRoute: route is up to date")
				return nil
			}
			logger.Info("manageVsystemRoute: updating route", "fields", strings.Join(updatedFields, ","))
			diff := cmp.Diff(route, &newRoute)
			logger.V(2).Info("manageVsystemRoute", "route diff", diff)
			err = client.Update(ctx, route)
			// an immutable field (like TLS certificate) has changed
			if errors.IsInvalid(err) {
				logger.Info("manageVsystemRoute: route update has been refused, replacing instead...",
					"error type", fmt.Sprintf("%T", err), "error", err)
				err := client.Delete(ctx, route)
				if err != nil && !errors.IsNotFound(err) {
					return err
				}
				err = client.Create(ctx, &newRoute)
			} else if err != nil {
				logger.Info("manageVsystemRoute: route update has been refused ...",
					"error type", fmt.Sprintf("%T", err), "error", err)
			}
		} else {
			logger.Info("manageVsystemRoute: creating a new route")
			err = client.Create(ctx, &newRoute)
		}
		return err
	})
	return err
}

func updateRoute(current, newRoute *routev1.Route) (bool, []string) {
	var changed bool
	var updatedFields = []string{}
	if current.Annotations == nil {
		current.Annotations = make(map[string]string)
	}
	for _, annKey := range []string{
		routeAnnotationTimeoutKey,
		opSdkPrimaryResourceTypeAnnotationKey,
		opSdkPrimaryResourceAnnotationKey,
	} {
		if current.Annotations[annKey] != newRoute.Annotations[annKey] {
			current.Annotations[annKey] = newRoute.Annotations[annKey]
			updatedFields = append(updatedFields, "annotations")
			changed = true
		}
	}
	if current.Labels == nil {
		current.Labels = make(map[string]string)
		changed = true
	}
	if !reflect.DeepEqual(current.Labels, newRoute.Labels) {
		current.Labels = newRoute.Labels
		updatedFields = append(updatedFields, "labels")
		changed = true
	}
	if !reflect.DeepEqual(current.ObjectMeta.OwnerReferences, newRoute.ObjectMeta.OwnerReferences) {
		current.ObjectMeta.OwnerReferences = newRoute.ObjectMeta.OwnerReferences
		updatedFields = append(updatedFields, "ownerReferences")
		changed = true
	}
	if !reflect.DeepEqual(current.Spec.Port, newRoute.Spec.Port) {
		current.Spec.Port = newRoute.Spec.Port
		updatedFields = append(updatedFields, "port")
		changed = true
	}
	if !reflect.DeepEqual(current.Spec.TLS, newRoute.Spec.TLS) {
		current.Spec.TLS = newRoute.Spec.TLS
		updatedFields = append(updatedFields, "tls")
		changed = true
	}
	if (current.Spec.Host != newRoute.Spec.Host && (len(newRoute.Spec.Host) > 0 || current.Annotations["openshift.io/host.generated"] != "true")) ||
		(len(newRoute.Spec.Host) > 0 && current.Annotations["openshift.io/host.generated"] == "true") {
		delete(current.Annotations, "openshift.io/host.generated")
		current.Spec.Host = newRoute.Spec.Host
		updatedFields = append(updatedFields, "host")
		changed = true
	}
	if current.Spec.To.Kind != newRoute.Spec.To.Kind || current.Spec.To.Name != newRoute.Spec.To.Name {
		current.Spec.To.Kind = newRoute.Spec.To.Kind
		current.Spec.To.Name = newRoute.Spec.To.Name
		updatedFields = append(updatedFields, "to")
		changed = true
	}
	return changed, updatedFields
}

func getRoutePortForVsystemService(svc *corev1.Service) *routev1.RoutePort {
	for _, sp := range svc.Spec.Ports {
		if sp.Name == "vsystem" || (sp.Port == vsystemPortNumber && sp.Protocol == "TCP") {
			return &routev1.RoutePort{
				TargetPort: intstr.FromString(sp.Name),
			}
		}
	}
	return nil
}

func getRouteLabelsForVsystemService(svc *corev1.Service) map[string]string {
	var labels = make(map[string]string)
	var reKey = regexp.MustCompile("^datahub\\.sap\\.com/")
	for k, v := range svc.ObjectMeta.Labels {
		if reKey.MatchString(k) {
			labels[k] = v
		}
	}
	return labels
}

func getCertFromCaBundleSecret(secret *corev1.Secret) (string, error) {
	if value, ok := secret.Data[vsystemCaBundleSecretKey]; !ok {
		return "", fmt.Errorf("failed to find key \"%s\" in \"%s\" secret!", vsystemCaBundleSecretKey, secret.ObjectMeta.Name)
	} else {
		return strings.TrimSpace(string(value[:])), nil
	}
}
