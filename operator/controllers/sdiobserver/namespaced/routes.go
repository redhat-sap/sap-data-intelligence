package namespaced

import (
	"context"
	"fmt"
	"reflect"
	"regexp"
	"strings"
	"time"

	"github.com/google/go-cmp/cmp"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/util/retry"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	routev1 "github.com/openshift/api/route/v1"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	λ "github.com/redhat-sap/sap-data-intelligence/operator/util/log"
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

func setConditions(
	owner *sdiv1alpha1.SDIObserver,
	status *sdiv1alpha1.ManagedRouteStatus,
	exposed, degraded metav1.ConditionStatus,
	reason, msg string,
) {
	meta.SetStatusCondition(&status.Conditions, metav1.Condition{
		Type:               "Exposed",
		Status:             exposed,
		Reason:             reason,
		Message:            msg,
		ObservedGeneration: owner.Generation,
	})
	meta.SetStatusCondition(&status.Conditions, metav1.Condition{
		Type:               "Degraded",
		Status:             degraded,
		Reason:             reason,
		Message:            msg,
		ObservedGeneration: owner.Generation,
	})
}

func manageVSystemRoute(
	ctx context.Context,
	scheme *runtime.Scheme,
	client client.Client,
	owner *sdiv1alpha1.SDIObserver,
	namespace string,
) error {
	tracer := λ.Enter(log.FromContext(ctx))
	defer λ.Leave(tracer)

	spec := owner.Spec.VSystemRoute
	if regexp.MustCompile(`^(\s*|(?i)Unmanaged)$`).MatchString(spec.ManagementState) {
		tracer.V(2).Info("vsystem route is not managed")
		setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionFalse,
			"Unmanaged", "the vsystem route is not managed by this SDIObserver instance")
		return nil
	}

	svcKey := types.NamespacedName{
		Namespace: namespace,
		Name:      "vsystem",
	}

	svc := &corev1.Service{}
	svcGetErr := client.Get(ctx, types.NamespacedName{
		Namespace: namespace,
		Name:      "vsystem",
	}, svc)
	if svcGetErr != nil && !errors.IsNotFound(svcGetErr) {
		tracer.Error(svcGetErr, "failed to get vsystem service")
		setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionTrue,
			"FailedGet", fmt.Sprintf("failed to get vsystem service: %v", svcGetErr))
		return svcGetErr
	}

	err := retry.RetryOnConflict(retry.DefaultRetry, func() error {
		route := &routev1.Route{}
		routeGetErr := client.Get(ctx, svcKey, route)
		if routeGetErr != nil && !errors.IsNotFound(routeGetErr) {
			tracer.Error(routeGetErr, "failed to get vsystem route")
			setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionTrue,
				"FailedGet", fmt.Sprintf("failed to get vsystem route: %v", svcGetErr))
			return routeGetErr
		}

		if regexp.MustCompile("^(?i)removed?$").MatchString(spec.ManagementState) || errors.IsNotFound(svcGetErr) {
			if errors.IsNotFound(routeGetErr) {
				msg := "vsystem route is removed"
				if errors.IsNotFound(svcGetErr) {
					msg += " due to missing service"
				} else {
					msg += " as instructed"
				}
				tracer.Info("vsystem route already removed, nothing to do", "message", msg)
				setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionFalse, metav1.ConditionFalse,
					"Removed", msg)
				return nil
			}
			tracer.Info("deleting vsystem route")
			if err := client.Delete(ctx, route); err != nil {
				if !errors.IsNotFound(err) {
					tracer.Error(err, "failed to delete vsystem route")
					setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionTrue, "FailedDelete",
						fmt.Sprintf("failed to delete vsystem route: %v", svcGetErr))
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
			tracer.Error(err, "failed to get vsystem/vora ca-bundle.pem secret")
			setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionTrue,
				"FailedGet", fmt.Sprintf("failed to get vsystem/vora ca-bundle.pem secret: %v", err))
			return err
		}
		caBundle, err := getCertFromCaBundleSecret(caBundleSecret)
		if err != nil {
			setConditions(owner, &owner.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionTrue,
				"InvalidSecret", fmt.Sprintf("%v", err))
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
						Kind:  "SDIObserver",
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
		if len(spec.Hostname) > 0 {
			newRoute.Spec.Host = spec.Hostname
		}

		if routeGetErr == nil && len(route.UID) > 0 {
			changed, updatedFields := updateRoute(route, &newRoute)
			if !changed {
				tracer.Info("route is up to date")
				setStatusForUptodateRoute(ctx, owner, route)
				return nil
			}

			tracer.Info("updating route", "fields", strings.Join(updatedFields, ","))
			diff := cmp.Diff(route, &newRoute)
			tracer.V(3).Info("route diff on Update", "diff", diff)
			err = client.Update(ctx, route)
			// an immutable field (like TLS certificate) has changed
			if errors.IsInvalid(err) {
				tracer.Info("route update has been refused, replacing instead...",
					"error type", fmt.Sprintf("%T", err), "error", err)
				err := client.Delete(ctx, route)
				if err != nil && !errors.IsNotFound(err) {
					// TODO set status
					return err
				}
				err = client.Create(ctx, &newRoute)
				return err
			}
			if err != nil {
				tracer.Info("route update has been refused ...",
					"error type", fmt.Sprintf("%T", err), "error", err)
			}
		} else {
			tracer.Info("creating a new route")
			err = client.Create(ctx, &newRoute)
		}
		return err
	})
	// TODO set status
	return err
}

// TODO(miminar) move to route utility module
func findRouteIngressCondition(
	conditions []routev1.RouteIngressCondition,
	conditionType routev1.RouteIngressConditionType,
) *routev1.RouteIngressCondition {
	for i := range conditions {
		if conditions[i].Type == conditionType {
			return &conditions[i]
		}
	}
	return nil
}

func isAnyRouteIngressAdmitted(route *routev1.Route) bool {
	for _, ingress := range route.Status.Ingress {
		c := findRouteIngressCondition(ingress.Conditions, "Admitted")
		if c != nil && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

func setStatusForUptodateRoute(ctx context.Context, obs *sdiv1alpha1.SDIObserver, route *routev1.Route) {
	tracer := λ.Enter(log.FromContext(ctx))
	defer λ.Leave(tracer)

	if isAnyRouteIngressAdmitted(route) {
		setConditions(obs, &obs.Status.VSystemRoute, metav1.ConditionTrue, metav1.ConditionFalse,
			"Admitted", "the route is up to date and admitted")
		return
	}

	msg := "the route is up to date but has not been admitted"
	now := time.Now()
	aMinuteAgo := metav1.NewTime(now.Add(-time.Minute))
	c := meta.FindStatusCondition(obs.Status.VSystemRoute.Conditions, "Exposed")
	if c != nil && c.Reason == sdiv1alpha1.ConditionRouteNotAdmitted && c.LastTransitionTime.Before(&aMinuteAgo) {
		// If the route hasn't been admitted for more then a minute, switch to degraded
		msg += " for more than " + now.Sub(c.LastTransitionTime.Time).String()
		setConditions(obs, &obs.Status.VSystemRoute, metav1.ConditionFalse, metav1.ConditionTrue,
			sdiv1alpha1.ConditionRouteNotAdmitted, msg)
		return
	}

	if c != nil && c.Reason != sdiv1alpha1.ConditionRouteNotAdmitted {
		msg += fmt.Sprintf(" (Reason=%s): %s", c.Reason, c.Message)
		setConditions(obs, &obs.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionFalse,
			sdiv1alpha1.ConditionRouteNotAdmitted, msg)
		return
	}

	setConditions(obs, &obs.Status.VSystemRoute, metav1.ConditionUnknown, metav1.ConditionFalse,
		sdiv1alpha1.ConditionRouteNotAdmitted, msg)
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
	var reKey = regexp.MustCompile(`^datahub\.sap\.com/`)
	for k, v := range svc.ObjectMeta.Labels {
		if reKey.MatchString(k) {
			labels[k] = v
		}
	}
	return labels
}

func getCertFromCaBundleSecret(secret *corev1.Secret) (string, error) {
	value, ok := secret.Data[vsystemCaBundleSecretKey]
	if !ok {
		return "", fmt.Errorf("failed to find key \"%s\" in \"%s\" secret", vsystemCaBundleSecretKey, secret.ObjectMeta.Name)
	}
	return strings.TrimSpace(string(value[:])), nil
}
