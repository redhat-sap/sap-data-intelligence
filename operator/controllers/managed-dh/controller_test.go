package managed_dh

import (
	"context"
	"fmt"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	"sigs.k8s.io/controller-runtime/pkg/client"

	//+kubebuilder:scaffold:imports

	routev1 "github.com/openshift/api/route/v1"
	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

const (
	vsystemCabundle = "-----BEGIN CERTIFICATE-----\nMIIDnDCCAoSgAwIBAgIRAOJtcKiXAFehwcYmJ5jxt64wDQYJKoZIhvcNAQELBQAw\ndzELMAkGA1UEBhMCREUxCzAJBgNVBAgTAkJXMREwDwYDVQQHEwhXYWxsZG9yZjEM\nMAoGA1UEChMDU0FQMREwDwYDVQQLEwhEYXRhIEh1YjEnMCUGA1UEAxMeU0FQRGF0\nYUludGVsbGlnZW5jZS0xNjM3MDAwMDk3MB4XDTIxMTExNTE4MTQ1N1oXDTMxMTEx\nMzE4MTQ1N1owdzELMAkGA1UEBhMCREUxCzAJBgNVBAgTAkJXMREwDwYDVQQHEwhX\nYWxsZG9yZjEMMAoGA1UEChMDU0FQMREwDwYDVQQLEwhEYXRhIEh1YjEnMCUGA1UE\nAxMeU0FQRGF0YUludGVsbGlnZW5jZS0xNjM3MDAwMDk3MIIBIjANBgkqhkiG9w0B\nAQEFAAOCAQ8AMIIBCgKCAQEA3vWXAhkzu6DTWVHZEyYkl16wzxbuI52XeNnUXGYU\n8EahnCaDo7qw3NDSedpDfnU2aMiA0yilNnVaRQJFOLNqTegAQvcPhxVlgzFGGMQ8\nQdjqtIVLy4mdaaoXieMBbm3mX//UyafKLgDdfeeruVEm8on77I1er4W+MCSULGkS\naBn1mkzOsbb+QTBKEy8Z8hJ+WKFMImunc16MeeMumRRm8CTyn0Uu8eobHpzAkdUw\n4RegfU0f07ULTMhHRPylC+hXQqtnB6pOR8r8YYnvgbOxU6MIuuQQxquCxh4Pl6X0\ncsjMMLx4KWPmjWMU51X66vgSnQJQ60sRo1TaP/TKg+JnsQIDAQABoyMwITAOBgNV\nHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEA\nuI26+6xe1/0/UzeM8SV+Z8WJ4Hnv3FnoDwI5UHViD9rzzdFDlFcLieT1wGph8dhV\n4hTov2qbwM3j2sK9ZajKXL/YImy7kZQWzyTrUg/dVefaDDpTpgPgU48mD2n4O5Zk\nSh+kvHqRVkCQ3SnVW4+4bhlfuRJ/Z1hnK/Jgilp2aU/k8Rn6rNnqPyFh0r4tFuNg\nPB1TXGPF4ghuQDtRl6r0ojXPbMi3aWlkopjctSxk5tLXsQ/4Kw2eJaGM0uin0iEz\nYvoEqCIpZQWuZGOn4q/RJ4MEs3HNrsy62OhRRoMLROD/DdcD3kFFQ5cNvRuh/yJg\nCx93V+7DGphJcPTJfZC6hA==\n-----END CERTIFICATE-----\n"
)

// These tests use Ginkgo (BDD-style Go testing framework). Refer to
// http://onsi.github.io/ginkgo/ to learn more about Ginkgo.

func mkVsystemService(namespace string) *corev1.Service {
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

func mkVsystemRoute(namespace string) *routev1.Route {
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

func mkVsystemCabundleSecret(namespace string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "ca-bundle.pem",
			Namespace: namespace,
		},
		StringData: map[string]string{
			"ca-bundle.pem": vsystemCabundle,
		},
	}
}

var _ = Describe("ManagedDh controller", func() {
	// Define utility constants for object names and testing timeouts/durations and intervals.
	const (
		timeout  = time.Second * 10
		duration = time.Second * 10
		interval = time.Millisecond * 250
	)

	checkRoute := func(route *routev1.Route, expectedCaBundle string, expectedHost *string) {
		Expect(route).NotTo(BeNil())
		Expect(route.Labels).To(Equal(
			map[string]string{
				"datahub.sap.com/app":             "vsystem",
				"datahub.sap.com/app-component":   "vsystem",
				"datahub.sap.com/app-version":     "3.2.21",
				"datahub.sap.com/package-version": "3.2.34",
			},
		))
		Expect(route.Annotations).To(
			HaveKeyWithValue("haproxy.router.openshift.io/timeout", "2m"))
		Expect(route.Annotations).To(
			HaveKeyWithValue("operator-sdk/primary-resource-type", "SdiObserver.di.sap-cop.redhat.com"))
		Expect(route.Annotations).To(
			HaveKeyWithValue("operator-sdk/primary-resource", "sdi-observer/sdi"))
		Expect(route.Spec.TLS).NotTo(BeNil())
		Expect(string(route.Spec.TLS.Termination)).To(Equal("reencrypt"))
		Expect(strings.TrimSpace(route.Spec.TLS.DestinationCACertificate)).To(
			Equal(strings.TrimSpace(expectedCaBundle)))
		Expect(route.Spec.TLS.CACertificate).To(Equal(""))
		Expect(string(route.Spec.TLS.InsecureEdgeTerminationPolicy)).To(Equal("Redirect"))
		Expect(route.Spec.TLS.Key).To(Equal(""))
		if expectedHost == nil {
			// with a real OpenShift API server, this would be set by an admission controller
			Expect(route.Spec.Host).To(Equal(""))
		} else {
			Expect(route.Spec.Host).To(Equal(*expectedHost))
		}
	}

	BeforeEach(func() {
		Expect(k8sClient.Create(context.TODO(), mkVsystemCabundleSecret("sdi"))).ShouldNot(HaveOccurred())
	})

	AfterEach(func() {
		toDelete := []struct {
			obj             client.Object
			namespace, name string
		}{
			{obj: &corev1.Service{}, namespace: "sdi", name: "vsystem"},
			{obj: &corev1.Secret{}, namespace: "sdi", name: "ca-bundle.pem"},
			{obj: &routev1.Route{}, namespace: "sdi", name: "vsystem"},
			{obj: &sdiv1alpha1.SdiObserver{}, namespace: "sdi-observer", name: "sdi"},
		}
		for _, td := range toDelete {
			td.obj.SetName(td.name)
			td.obj.SetNamespace(td.namespace)
			err := k8sClient.Delete(context.TODO(), td.obj)
			Expect(err == nil || errors.IsNotFound(err)).Should(BeTrue())
		}
	})

	Context("When managing vsystem route", func() {
		It("Should create the corresponding route", func() {
			By("Seeing it missing")
			ctx := context.Background()
			Expect(k8sClient.Create(ctx, mkVsystemService("sdi"))).ShouldNot(HaveOccurred())

			obs := &sdiv1alpha1.SdiObserver{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "sdi",
					Namespace: "sdi-observer",
				},
				Spec: sdiv1alpha1.SdiObserverSpec{
					SdiNamespace: "sdi",
					VsystemRoute: sdiv1alpha1.SdiObserverSpecRoute{
						ManagementState: sdiv1alpha1.RouteManagementStateManaged,
					},
				},
			}
			Expect(k8sClient.Create(ctx, obs)).NotTo(HaveOccurred())

			var fetched routev1.Route
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())

			checkRoute(&fetched, vsystemCabundle, nil)

			fmt.Fprintf(GinkgoWriter, "Removing the route manually ...\n")
			Expect(k8sClient.Delete(ctx, &fetched)).NotTo(HaveOccurred())

			By("Restoring it when manually deleted")
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())

			checkRoute(&fetched, vsystemCabundle, nil)
		})

		It("Should delete the corresponding route", func() {
			By("Observing management state")
			ctx := context.Background()
			Expect(k8sClient.Create(ctx, mkVsystemService("sdi"))).ShouldNot(HaveOccurred())

			var fetched routev1.Route
			err := k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi",
				Name:      "vsystem",
			}, &fetched)
			Expect(err).Should(HaveOccurred())
			Expect(errors.IsNotFound(err)).Should(BeTrue())

			Expect(k8sClient.Create(ctx, mkVsystemRoute("sdi"))).ShouldNot(HaveOccurred())

			obs := &sdiv1alpha1.SdiObserver{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "sdi",
					Namespace: "sdi-observer",
				},
				Spec: sdiv1alpha1.SdiObserverSpec{
					SdiNamespace: "sdi",
					VsystemRoute: sdiv1alpha1.SdiObserverSpecRoute{
						ManagementState: sdiv1alpha1.RouteManagementStateRemoved,
					},
				},
			}
			Expect(k8sClient.Create(ctx, obs)).NotTo(HaveOccurred())

			// the controller does not watch the SdiObserver resource on its own, it relies on being notified
			// by the parent controller
			obsController.ReconcileObs(obs)

			Eventually(func() bool {
				err := k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
				ret := errors.IsNotFound(err)
				if !ret {
					fmt.Fprintf(GinkgoWriter, "Got %v (type=%T) instead of IsNotFound.\n", err, err)
				}
				return ret
			}, timeout, interval).Should(BeTrue())

			By("Noticing the removal of the vsystem service")

			fmt.Fprintf(GinkgoWriter, "Setting management state to Managed...\n")
			Expect(k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi-observer",
				Name:      "sdi",
			}, obs)).NotTo(HaveOccurred())
			obs.Spec.VsystemRoute.ManagementState = sdiv1alpha1.RouteManagementStateManaged
			Expect(k8sClient.Update(ctx, obs)).NotTo(HaveOccurred())

			fmt.Fprintf(GinkgoWriter, "Notifying the controller about SdiObserver change...\n")
			obsController.ReconcileObs(obs)

			fmt.Fprintf(GinkgoWriter, "Ensuring the route gets recreated...\n")
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())
			checkRoute(&fetched, vsystemCabundle, nil)

			fmt.Fprintf(GinkgoWriter, "Removing the service ...\n")
			Expect(k8sClient.Delete(ctx, mkVsystemService("sdi"))).NotTo(HaveOccurred())

			Eventually(func() bool {
				err := k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
				ret := errors.IsNotFound(err)
				if !ret {
					fmt.Fprintf(GinkgoWriter, "Got %v (type=%T) instead of IsNotFound.\n", err, err)
				}
				return ret
			}, timeout, interval).Should(BeTrue())
		})

		It("Should update an existing route", func() {
			By("Replacing an unmanaged one")
			ctx := context.Background()
			Expect(k8sClient.Create(ctx, mkVsystemRoute("sdi"))).ShouldNot(HaveOccurred())
			Expect(k8sClient.Create(ctx, mkVsystemService("sdi"))).ShouldNot(HaveOccurred())

			var origRoute routev1.Route
			Expect(k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi",
				Name:      "vsystem",
			}, &origRoute)).NotTo(HaveOccurred())

			obs := &sdiv1alpha1.SdiObserver{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "sdi",
					Namespace: "sdi-observer",
				},
				Spec: sdiv1alpha1.SdiObserverSpec{
					SdiNamespace: "sdi",
					VsystemRoute: sdiv1alpha1.SdiObserverSpecRoute{
						ManagementState: sdiv1alpha1.RouteManagementStateManaged,
					},
				},
			}
			Expect(k8sClient.Create(ctx, obs)).NotTo(HaveOccurred())
			obsController.ReconcileObs(obs)

			var updatedRoute routev1.Route
			Eventually(func() bool {
				err := k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)
				return err == nil && updatedRoute.ResourceVersion != origRoute.ResourceVersion
			}, timeout, interval).Should(BeTrue())
			checkRoute(&updatedRoute, vsystemCabundle, nil)

			By("An update to the managed route spec")
			const customHost = "my-vsystem.apps.example.com"
			Expect(k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi-observer",
				Name:      "sdi",
			}, obs)).NotTo(HaveOccurred())
			obs.Spec.VsystemRoute.Hostname = customHost
			Expect(k8sClient.Update(ctx, obs)).NotTo(HaveOccurred())
			obsController.ReconcileObs(obs)

			origRoute = *updatedRoute.DeepCopy()
			Eventually(func() string {
				err := k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)
				Expect(err).NotTo(HaveOccurred())
				return updatedRoute.Spec.Host
			}, timeout, interval).Should(Equal(customHost))
			var host = customHost
			checkRoute(&updatedRoute, vsystemCabundle, &host)

			By("A manual update to the managed route")
			updatedRoute.Spec.TLS.DestinationCACertificate = "bar"
			updatedRoute.Spec.Host = "foo"
			Expect(k8sClient.Update(ctx, &updatedRoute)).NotTo(HaveOccurred())

			Eventually(func() string {
				err := k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)
				Expect(err).NotTo(HaveOccurred())
				return updatedRoute.Spec.Host
			}, timeout, interval).Should(Equal(customHost))

			By("An update to the ca secret")
			secret := mkVsystemCabundleSecret("sdi")
			secret.StringData["ca-bundle.pem"] = "foo  \n"
			Expect(k8sClient.Update(ctx, secret)).NotTo(HaveOccurred())

			Eventually(func() string {
				err := k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)
				Expect(err).NotTo(HaveOccurred())
				return updatedRoute.Spec.TLS.DestinationCACertificate
			}, timeout, interval).Should(Equal("foo"))
		})
	})
})
