package namespaced_test

import (
	"context"
	"fmt"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	//+kubebuilder:scaffold:imports
	routev1 "github.com/openshift/api/route/v1"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	testapi "github.com/redhat-sap/sap-data-intelligence/operator/test/api"
	testroutes "github.com/redhat-sap/sap-data-intelligence/operator/test/routes"
	ωbs "github.com/redhat-sap/sap-data-intelligence/operator/test/sdiobservers"
)

// These tests use Ginkgo (BDD-style Go testing framework). Refer to
// http://onsi.github.io/ginkgo/ to learn more about Ginkgo.

var _ = Describe("Namespaced SDI Observer controller", func() {
	// Define utility constants for object names and testing timeouts/durations and intervals.
	const (
		timeout = time.Second * 10
		//duration = time.Second * 10
		interval = time.Millisecond * 250
	)

	checkRoute := func(route *routev1.Route, expectedCaBundle string, expectedHost *string) {
		Ω(route).NotTo(BeNil())
		Ω(route.Labels).To(Equal(
			map[string]string{
				"datahub.sap.com/app":             "vsystem",
				"datahub.sap.com/app-component":   "vsystem",
				"datahub.sap.com/app-version":     "3.2.21",
				"datahub.sap.com/package-version": "3.2.34",
			},
		))
		Ω(route.Annotations).To(SatisfyAll(
			HaveKeyWithValue("haproxy.router.openshift.io/timeout", "2m"),
			HaveKeyWithValue("operator-sdk/primary-resource-type", "SDIObserver.di.sap-cop.redhat.com"),
			HaveKeyWithValue("operator-sdk/primary-resource", "sdi-observer/sdi")))
		Ω(route.Spec.TLS).NotTo(BeNil())
		Ω(string(route.Spec.TLS.Termination)).To(Equal("reencrypt"))
		Ω(strings.TrimSpace(route.Spec.TLS.DestinationCACertificate)).To(
			Equal(strings.TrimSpace(expectedCaBundle)))
		Ω(route.Spec.TLS.CACertificate).To(Equal(""))
		Ω(string(route.Spec.TLS.InsecureEdgeTerminationPolicy)).To(Equal("Redirect"))
		Ω(route.Spec.TLS.Key).To(Equal(""))
		if expectedHost == nil {
			// with a real OpenShift API server, this would be set by an admission controller
			Ω(route.Spec.Host).To(Equal(""))
		} else {
			Ω(route.Spec.Host).To(Equal(*expectedHost))
		}
	}

	createObs := func(vsystemManagementState string) *sdiv1alpha1.SDIObserver {
		ctx := context.Background()
		obs := &sdiv1alpha1.SDIObserver{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "sdi",
				Namespace: "sdi-observer",
			},
			Spec: sdiv1alpha1.SDIObserverSpec{
				SDINamespace: "sdi",
				VSystemRoute: sdiv1alpha1.SDIObserverSpecRoute{
					ManagementState: vsystemManagementState,
				},
			},
		}
		Ω(k8sClient.Create(ctx, obs)).NotTo(HaveOccurred())
		return obs
	}

	BeforeEach(func() {
		Ω(k8sClient.Create(context.Background(), testroutes.MakeVSystemCABundleSecret("sdi"))).ShouldNot(HaveOccurred())
	})

	AfterEach(func() {
		fmt.Fprintf(GinkgoWriter, "Cleaning up the sdi namespace...\n")
		toDelete := []struct {
			obj             client.Object
			namespace, name string
		}{
			{obj: &corev1.Service{}, namespace: "sdi", name: "vsystem"},
			{obj: &corev1.Secret{}, namespace: "sdi", name: "ca-bundle.pem"},
			{obj: &routev1.Route{}, namespace: "sdi", name: "vsystem"},
			{obj: &sdiv1alpha1.SDIObserver{}, namespace: "sdi-observer", name: "sdi"},
		}
		for _, td := range toDelete {
			td.obj.SetName(td.name)
			td.obj.SetNamespace(td.namespace)
			err := k8sClient.Delete(context.Background(), td.obj)
			Ω(err).Should(Or(BeNil(), testapi.FailWithStatus(metav1.StatusReasonNotFound)))
		}
	})

	Context("When the admission of a route takes too long", func() {
		It("Should become degraded", func() {
			ctx := context.Background()
			Ω(k8sClient.Create(ctx, testroutes.MakeVSystemService("sdi"))).ShouldNot(HaveOccurred())
			obs := createObs(sdiv1alpha1.RouteManagementStateManaged)

			var fetched routev1.Route
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())

			checkRoute(&fetched, testroutes.VSystemCABundle, nil)
			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(And(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionUnknown, "NotAdmitted"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "NotAdmitted")))
				g.Ω(obs).To(And(
					ωbs.HaveConditionReason("Progressing", metav1.ConditionTrue, "Ingress"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "AsExpected"),
					ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected")))
			})

			ωbs.UpdateStatus(k8sClient, obs, func(obs *sdiv1alpha1.SDIObserver) {
				c := meta.FindStatusCondition(obs.Status.VSystemRoute.Conditions, "Exposed")
				Ω(sdiv1alpha1.RouteManagementStateManaged).NotTo(BeNil())
				c.LastTransitionTime = metav1.NewTime(c.LastTransitionTime.Add(-time.Minute * 2))
			})
			nmCtrl.ReconcileObs(obs)
			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(And(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionFalse, "NotAdmitted"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionTrue, "NotAdmitted")))
				g.Ω(obs).To(And(
					ωbs.HaveConditionReason("Progressing", metav1.ConditionFalse, "IngressBlocked"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionTrue, "Ingress"),
					ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected")))
			})

			By("Show the route as admitted and exposed")
			Expect(testroutes.AdmitRoute(k8sClient, &fetched)).NotTo(HaveOccurred())
			_ = k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi",
				Name:      "vsystem",
			}, &fetched)
			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(And(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionTrue, "Admitted"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "Admitted")))
				g.Ω(obs).To(And(
					ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected"),
					ωbs.HaveConditionReason("Progressing", metav1.ConditionFalse, "AsExpected"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "AsExpected")))
			})
		})
	})

	Context("When managing vsystem route", func() {
		It("Should create the corresponding route", func() {
			By("Seeing it missing")
			ctx := context.Background()
			Ω(k8sClient.Create(ctx, testroutes.MakeVSystemService("sdi"))).ShouldNot(HaveOccurred())

			obs := createObs(sdiv1alpha1.RouteManagementStateManaged)

			var fetched routev1.Route
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())

			checkRoute(&fetched, testroutes.VSystemCABundle, nil)
			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(And(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionUnknown, "NotAdmitted"),
					ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "NotAdmitted")))
			})

			By("Show the route as admitted and exposed")
			Expect(testroutes.AdmitRoute(k8sClient, &fetched)).NotTo(HaveOccurred())
			_ = k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi",
				Name:      "vsystem",
			}, &fetched)
			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionTrue, "Admitted"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Progressing", metav1.ConditionFalse, "AsExpected"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "AsExpected"))
			})

			fmt.Fprintf(GinkgoWriter, "Removing the route manually ...\n")
			Ω(k8sClient.Delete(ctx, &fetched)).NotTo(HaveOccurred())

			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionUnknown, "NotAdmitted"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Progressing", metav1.ConditionTrue, "Ingress"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "AsExpected"))
			})

			By("Restoring it when manually deleted")
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())

			checkRoute(&fetched, testroutes.VSystemCABundle, nil)

			Expect(testroutes.AdmitRoute(k8sClient, &fetched)).NotTo(HaveOccurred())
			ωbs.WaitForObserverState(k8sClient, 0, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
				g.Ω(obs.Status.VSystemRoute).To(
					ωbs.HaveConditionReason("Exposed", metav1.ConditionTrue, "Admitted"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Progressing", metav1.ConditionFalse, "AsExpected"))
				g.Ω(obs).To(ωbs.HaveConditionReason("Degraded", metav1.ConditionFalse, "AsExpected"))
			})
		})

		It("Should delete the corresponding route", func() {
			By("Observing management state")
			ctx := context.Background()
			Ω(k8sClient.Create(ctx, testroutes.MakeVSystemService("sdi"))).ShouldNot(HaveOccurred())

			var fetched routev1.Route
			err := k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi",
				Name:      "vsystem",
			}, &fetched)
			Ω(err).To(testapi.FailWithStatus(metav1.StatusReasonNotFound))

			Ω(k8sClient.Create(ctx, testroutes.MakeVSystemRoute("sdi"))).ShouldNot(HaveOccurred())

			obs := createObs(sdiv1alpha1.RouteManagementStateRemoved)

			// the controller does not watch the SDIObserver resource on its own, it relies on being notified
			// by the parent controller
			nmCtrl.ReconcileObs(obs)

			Eventually(func(g Gomega) {
				err := k8sClient.Get(ctx, types.NamespacedName{Namespace: "sdi", Name: "vsystem"}, &fetched)
				g.Ω(err).To(testapi.FailWithStatus(metav1.StatusReasonNotFound))
			}, timeout, interval).Should(Succeed())

			By("Noticing the removal of the vsystem service")
			fmt.Fprintf(GinkgoWriter, "Setting management state to Managed...\n")
			ωbs.Update(k8sClient, obs, func(obs *sdiv1alpha1.SDIObserver) {
				obs.Spec.VSystemRoute.ManagementState = sdiv1alpha1.RouteManagementStateManaged
			})

			fmt.Fprintf(GinkgoWriter, "Notifying the controller about SDIObserver change...\n")
			nmCtrl.ReconcileObs(obs)

			fmt.Fprintf(GinkgoWriter, "Ensuring the route gets recreated...\n")
			Eventually(func() error {
				return k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)
			}, timeout, interval).ShouldNot(HaveOccurred())
			checkRoute(&fetched, testroutes.VSystemCABundle, nil)

			fmt.Fprintf(GinkgoWriter, "Removing the service ...\n")
			Ω(k8sClient.Delete(ctx, testroutes.MakeVSystemService("sdi"))).NotTo(HaveOccurred())
			Eventually(func(g Gomega) {
				g.Ω(k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &fetched)).To(testapi.FailWithStatus(metav1.StatusReasonNotFound))
			}, timeout, interval).Should(Succeed())
		})

		It("Should update an existing route", func() {
			By("Replacing an unmanaged one")
			ctx := context.Background()
			Ω(k8sClient.Create(ctx, testroutes.MakeVSystemRoute("sdi"))).ShouldNot(HaveOccurred())
			Ω(k8sClient.Create(ctx, testroutes.MakeVSystemService("sdi"))).ShouldNot(HaveOccurred())

			var origRoute routev1.Route
			Ω(k8sClient.Get(ctx, types.NamespacedName{
				Namespace: "sdi",
				Name:      "vsystem",
			}, &origRoute)).NotTo(HaveOccurred())

			obs := createObs(sdiv1alpha1.RouteManagementStateManaged)
			nmCtrl.ReconcileObs(obs)

			var updatedRoute routev1.Route
			Eventually(func(g Gomega) {
				g.Ω(k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)).NotTo(HaveOccurred())
				g.Ω(updatedRoute.ResourceVersion).NotTo(Equal(origRoute.ResourceVersion))
			}, timeout, interval).Should(Succeed())
			checkRoute(&updatedRoute, testroutes.VSystemCABundle, nil)

			By("An update to the managed route spec")
			const customHost = "my-vsystem.apps.example.com"
			ωbs.Update(k8sClient, obs, func(obs *sdiv1alpha1.SDIObserver) {
				obs.Spec.VSystemRoute.Hostname = customHost
			})
			nmCtrl.ReconcileObs(obs)

			origRoute = *updatedRoute.DeepCopy()
			Eventually(func(g Gomega) {
				g.Ω(k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)).NotTo(HaveOccurred())
				g.Ω(updatedRoute.Spec.Host).To(Equal(customHost))
			}, timeout, interval).Should(Succeed())
			var host = customHost
			checkRoute(&updatedRoute, testroutes.VSystemCABundle, &host)

			By("A manual update to the managed route")
			updatedRoute.Spec.TLS.DestinationCACertificate = "bar"
			updatedRoute.Spec.Host = "foo"
			Ω(k8sClient.Update(ctx, &updatedRoute)).NotTo(HaveOccurred())

			Eventually(func(g Gomega) {
				g.Ω(k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)).NotTo(HaveOccurred())
				g.Ω(updatedRoute.Spec.Host).To(Equal(customHost))
			}, timeout, interval).Should(Succeed())

			By("An update to the ca secret")
			secret := testroutes.MakeVSystemCABundleSecret("sdi")
			secret.StringData["ca-bundle.pem"] = "foo  \n"
			Ω(k8sClient.Update(ctx, secret)).NotTo(HaveOccurred())

			Eventually(func(g Gomega) {
				g.Ω(k8sClient.Get(ctx, types.NamespacedName{
					Namespace: "sdi",
					Name:      "vsystem",
				}, &updatedRoute)).NotTo(HaveOccurred())
				g.Ω(updatedRoute.Spec.TLS.DestinationCACertificate).To(Equal("foo"))
			}, timeout, interval).Should(Succeed())
		})
	})
})
