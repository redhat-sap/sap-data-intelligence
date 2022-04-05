package routes

import (
	"context"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/util/retry"
	"sigs.k8s.io/controller-runtime/pkg/client"

	routev1 "github.com/openshift/api/route/v1"
)

const (
	VSystemCABundle = "-----BEGIN CERTIFICATE-----\nMIIDnDCCAoSgAwIBAgIRAOJtcKiXAFehwcYmJ5jxt64wDQYJKoZIhvcNAQELBQAw\ndzELMAkGA1UEBhMCREUxCzAJBgNVBAgTAkJXMREwDwYDVQQHEwhXYWxsZG9yZjEM\nMAoGA1UEChMDU0FQMREwDwYDVQQLEwhEYXRhIEh1YjEnMCUGA1UEAxMeU0FQRGF0\nYUludGVsbGlnZW5jZS0xNjM3MDAwMDk3MB4XDTIxMTExNTE4MTQ1N1oXDTMxMTEx\nMzE4MTQ1N1owdzELMAkGA1UEBhMCREUxCzAJBgNVBAgTAkJXMREwDwYDVQQHEwhX\nYWxsZG9yZjEMMAoGA1UEChMDU0FQMREwDwYDVQQLEwhEYXRhIEh1YjEnMCUGA1UE\nAxMeU0FQRGF0YUludGVsbGlnZW5jZS0xNjM3MDAwMDk3MIIBIjANBgkqhkiG9w0B\nAQEFAAOCAQ8AMIIBCgKCAQEA3vWXAhkzu6DTWVHZEyYkl16wzxbuI52XeNnUXGYU\n8EahnCaDo7qw3NDSedpDfnU2aMiA0yilNnVaRQJFOLNqTegAQvcPhxVlgzFGGMQ8\nQdjqtIVLy4mdaaoXieMBbm3mX//UyafKLgDdfeeruVEm8on77I1er4W+MCSULGkS\naBn1mkzOsbb+QTBKEy8Z8hJ+WKFMImunc16MeeMumRRm8CTyn0Uu8eobHpzAkdUw\n4RegfU0f07ULTMhHRPylC+hXQqtnB6pOR8r8YYnvgbOxU6MIuuQQxquCxh4Pl6X0\ncsjMMLx4KWPmjWMU51X66vgSnQJQ60sRo1TaP/TKg+JnsQIDAQABoyMwITAOBgNV\nHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEA\nuI26+6xe1/0/UzeM8SV+Z8WJ4Hnv3FnoDwI5UHViD9rzzdFDlFcLieT1wGph8dhV\n4hTov2qbwM3j2sK9ZajKXL/YImy7kZQWzyTrUg/dVefaDDpTpgPgU48mD2n4O5Zk\nSh+kvHqRVkCQ3SnVW4+4bhlfuRJ/Z1hnK/Jgilp2aU/k8Rn6rNnqPyFh0r4tFuNg\nPB1TXGPF4ghuQDtRl6r0ojXPbMi3aWlkopjctSxk5tLXsQ/4Kw2eJaGM0uin0iEz\nYvoEqCIpZQWuZGOn4q/RJ4MEs3HNrsy62OhRRoMLROD/DdcD3kFFQ5cNvRuh/yJg\nCx93V+7DGphJcPTJfZC6hA==\n-----END CERTIFICATE-----\n"
)

func MakeVSystemService(namespace string) *corev1.Service {
	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "vsystem",
			Namespace: namespace,
			Annotations: map[string]string{
				"datahub.sap.com/prometheus_port":           "8125",
				"datahub.sap.com/prometheus_scheme":         "https",
				"datahub.sap.com/prometheus_scrape":         "true",
				"meta.helm.sh/release-name":                 "vsystem-0efffb",
				"meta.helm.sh/release-namespace":            "sdi",
				"service.alpha.kubernetes.io/app-protocols": "{\"vsystem\":\"HTTPS\"}",
			},
			Labels: map[string]string{
				"app.kubernetes.io/managed-by":    "Helm",
				"datahub.sap.com/app":             "vsystem",
				"datahub.sap.com/app-component":   "vsystem",
				"datahub.sap.com/app-version":     "3.2.21",
				"datahub.sap.com/package-version": "3.2.34",
			},
		},
		Spec: corev1.ServiceSpec{
			Ports: []corev1.ServicePort{
				{
					Name:       "vsystem",
					Port:       8797,
					Protocol:   "TCP",
					TargetPort: intstr.FromInt(8797),
				},
			},
			Selector: map[string]string{
				"datahub.sap.com/app":           "vsystem",
				"datahub.sap.com/app-component": "vsystem",
			},
			Type: corev1.ServiceTypeClusterIP,
		},
	}
}

func MakeVSystemRoute(namespace string) *routev1.Route {
	return &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "vsystem",
			Namespace: namespace,
		},
		Spec: routev1.RouteSpec{
			To: routev1.RouteTargetReference{
				Kind: "Service",
				Name: "vsystem",
			},
			Port: &routev1.RoutePort{
				TargetPort: intstr.FromString("vsystem"),
			},
		},
	}
}

func MakeVSystemCABundleSecret(namespace string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "ca-bundle.pem",
			Namespace: namespace,
		},
		StringData: map[string]string{
			"ca-bundle.pem": VSystemCABundle,
		},
	}
}

// FindRouteIngressCondition assumes there is just one ingress configured!
func FindRouteIngressCondition(
	r *routev1.Route,
	cType routev1.RouteIngressConditionType,
) (*routev1.RouteIngress, *routev1.RouteIngressCondition) {
	for _, i := range r.Status.Ingress {
		for _, c := range i.Conditions {
			if c.Type == routev1.RouteIngressConditionType(cType) {
				return &i, &c
			}
		}
	}
	return nil, nil
}

// SetRouteIngressCondition is only useful in tests!
// Inspired by k8s.io/apimachinery/pkg/api/meta/conditions.go
func SetRouteIngressCondition(
	r *routev1.Route,
	c *routev1.RouteIngressCondition,
) *routev1.RouteIngressCondition {
	if len(r.Status.Ingress) == 0 {
		r.Status.Ingress = []routev1.RouteIngress{
			{
				Host:       "foo.example.ltd",
				RouterName: "default",
			},
		}
	}

	_, existingCondition := FindRouteIngressCondition(r, c.Type)
	if existingCondition == nil {
		var ret *routev1.RouteIngressCondition
		for i := range r.Status.Ingress {
			ingress := &r.Status.Ingress[i]
			if c.LastTransitionTime.IsZero() {
				t := metav1.NewTime(time.Now())
				c.LastTransitionTime = &t
			}
			ingress.Conditions = append(ingress.Conditions, *c)
			if ret == nil {
				ret = &ingress.Conditions[len(ingress.Conditions)-1]
			}
		}
		return ret
	}

	if existingCondition.Status != c.Status {
		existingCondition.Status = c.Status
		if !c.LastTransitionTime.IsZero() {
			existingCondition.LastTransitionTime = c.LastTransitionTime
		} else {
			t := metav1.NewTime(time.Now())
			existingCondition.LastTransitionTime = &t
		}
	}

	existingCondition.Reason = c.Reason
	existingCondition.Message = c.Message
	return existingCondition
}

// AdmitRoute updates the status of the given route on k8s side with the Admitted ingress condition.
// It also updates the given route inplace.
func AdmitRoute(k8sClient client.Client, r *routev1.Route) error {
	ctx := context.Background()
	return retry.RetryOnConflict(retry.DefaultRetry, func() error {
		if err := k8sClient.Get(ctx, client.ObjectKeyFromObject(r), r); err != nil {
			return err
		}
		SetRouteIngressCondition(r, &routev1.RouteIngressCondition{
			Type:   "Admitted",
			Status: corev1.ConditionTrue,
		})
		return k8sClient.Update(ctx, r)
	})
}
