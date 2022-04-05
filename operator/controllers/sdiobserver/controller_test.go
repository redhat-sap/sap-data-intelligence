package sdiobserver_test

import (
	"context"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	routev1 "github.com/openshift/api/route/v1"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	dhv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/test/datahub/api/v1alpha1"
	testroutes "github.com/redhat-sap/sap-data-intelligence/operator/test/routes"
	ωbs "github.com/redhat-sap/sap-data-intelligence/operator/test/sdiobservers"
)

var _ = Describe("SDIObserver controller", func() {
	var obs *sdiv1alpha1.SDIObserver

	BeforeEach(func() {
		ctx := context.Background()
		obs = &sdiv1alpha1.SDIObserver{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: "sdi-observer",
				Name:      "sdi",
			},
			Spec: sdiv1alpha1.SDIObserverSpec{
				SDINamespace: "sdi",
				VSystemRoute: sdiv1alpha1.SDIObserverSpecRoute{
					ManagementState: sdiv1alpha1.RouteManagementStateManaged,
				},
			},
		}
		Ω(k8sClient.Create(ctx, obs)).NotTo(HaveOccurred())
	})

	AfterEach(func() {
		err := k8sClient.Delete(context.Background(), obs)
		if !errors.IsNotFound(err) {
			Ω(err).NotTo(HaveOccurred())
		}
	})

	Context("When no DH instance exists", func() {
		It("Should keep the managed reference unset", func() {
			ωbs.WaitForObserver(k8sClient, obs,
				ωbs.HaveConditionReason("Ready", metav1.ConditionFalse, sdiv1alpha1.ConditionReasonNotFound),
				ωbs.ReferenceDataHub(nil))
		})
	})

	Context("When a DH instance is removed", func() {
		BeforeEach(func() {
			dh := dhv1alpha1.GetSampleDH("sdi")
			Ω(dh).ShouldNot(BeNil())
			_, err := dhClient.Namespace("sdi").Create(context.TODO(), dh, metav1.CreateOptions{})
			Ω(err).NotTo(HaveOccurred())
		})

		AfterEach(func() {
			_ = dhClient.Namespace("sdi").Delete(context.TODO(), "default", metav1.DeleteOptions{})
		})

		It("Should delete all the owned objects", func() {

		})

		It("Should allow for its recreation", func() {
			ctx := context.Background()
			var uid types.UID
			ωbs.WaitForObserver(k8sClient, obs, ωbs.HaveCondition("Ready", ωbs.StatusTrue(), nil), ωbs.ReferenceDataHub(dhv1alpha1.GetSampleDH("sdi")))
			uid = obs.Status.ManagedDataHubRef.UID

			By("Deleting the managed DH instance")
			Ω(dhClient.Namespace("sdi").Delete(ctx, "default", metav1.DeleteOptions{})).NotTo(HaveOccurred())

			By("Waiting for the Observer to become idle")
			ωbs.WaitForObserver(k8sClient, obs,
				ωbs.ReferenceDataHub(nil),
				ωbs.HaveConditionReason("Ready", metav1.ConditionFalse, sdiv1alpha1.ConditionReasonNotFound),
				ωbs.HaveConditionStatus("Degraded", metav1.ConditionFalse),
				ωbs.HaveConditionReason("Progressing", metav1.ConditionFalse, sdiv1alpha1.ConditionReasonNotFound))

			// TODO: check that the owned objects have been deleted

			dh := dhv1alpha1.GetSampleDH("sdi")
			Ω(dh).ShouldNot(BeNil())
			_, err := dhClient.Namespace("sdi").Create(context.TODO(), dh, metav1.CreateOptions{})
			Ω(err).NotTo(HaveOccurred())

			ωbs.WaitForObserver(k8sClient, obs,
				ωbs.HaveCondition("Ready", ωbs.StatusTrue(), nil),
				ωbs.ReferenceDataHub(dhv1alpha1.GetSampleDH("sdi")))
			Ω(uid).NotTo(Equal(obs.Status.ManagedDataHubRef.UID))
		})
	})

	Context("When three SDIObserver instances compete for management", func() {
		It("Should deterministically pick the closest", func() {

		})
	})

	Context("When SDIObserver instance is deleted", func() {
		It("Should delete owned resources", func() {

		})

		BeforeEach(func() {
			dh := dhv1alpha1.GetSampleDH("sdi")
			Ω(dh).ShouldNot(BeNil())
			_, err := dhClient.Namespace("sdi").Create(context.TODO(), dh, metav1.CreateOptions{})
			Ω(err).NotTo(HaveOccurred())
		})

		AfterEach(func() {
			_ = dhClient.Namespace("sdi").Delete(context.TODO(), "default", metav1.DeleteOptions{})
			ctx := context.Background()
			_ = k8sClient.Delete(ctx, &sdiv1alpha1.SDIObserver{
				ObjectMeta: metav1.ObjectMeta{Namespace: "sdi-observer", Name: "sdi-second"}})
		})

		It("Suitable blocked instance shlould take over", func() {
			ctx := context.Background()
			ωbs.WaitForObserver(k8sClient, obs, ωbs.HaveCondition("Ready", ωbs.StatusTrue(), nil))

			obs2nd := &sdiv1alpha1.SDIObserver{
				ObjectMeta: metav1.ObjectMeta{
					Namespace: "sdi-observer",
					Name:      "sdi-second",
				},
				Spec: sdiv1alpha1.SDIObserverSpec{
					SDINamespace: "sdi",
					VSystemRoute: sdiv1alpha1.SDIObserverSpecRoute{
						ManagementState: sdiv1alpha1.RouteManagementStateManaged,
					},
				},
			}
			By("Creating another SDIObserver instance managing the same DH namespace")
			Ω(k8sClient.Create(ctx, obs2nd)).NotTo(HaveOccurred())
			ωbs.WaitForObserver(k8sClient, obs2nd,
				ωbs.HaveConditionReason("Ready", metav1.ConditionUnknown, sdiv1alpha1.ConditionReasonBackup),
				ωbs.HaveCondition("Backup", ωbs.StatusTrue(), nil),
				ωbs.HaveCondition("Degraded", ωbs.StatusUnknown(), nil))

			By("Ensure that the original SDIObserver instance is active")
			ωbs.WaitForObserver(k8sClient, obs,
				ωbs.HaveCondition("Ready", ωbs.StatusTrue(), nil),
				ωbs.HaveCondition("Degraded", ωbs.StatusFalse(), nil))

			By("Deleting the original SDIObserver instance")
			Ω(k8sClient.Delete(ctx, obs)).NotTo(HaveOccurred())

			By("Ensuring that the new SDIObserver instance took over")
			ωbs.WaitForObserver(k8sClient, obs2nd,
				ωbs.HaveConditionReason("Ready", metav1.ConditionTrue, "AsExpected"),
				ωbs.HaveCondition("Backup", ωbs.StatusFalse(), nil),
				ωbs.HaveCondition("Degraded", ωbs.StatusFalse(), nil),
				ωbs.HaveCondition("Progressing", ωbs.StatusFalse(), nil))
		})
	})

	Context("When two SDIObserver instances manage two DataHubs", func() {
		It("Should pose no conflict", func() {

		})
	})

	Context("When SDINamespace is changed", func() {
		BeforeEach(func() {
			ctx := context.TODO()
			for _, nm := range []string{"sdi2nd"} {
				Ω(k8sClient.Create(ctx, &corev1.Namespace{
					ObjectMeta: metav1.ObjectMeta{
						Name: nm,
					},
				})).ToNot(HaveOccurred())
			}
			for _, nm := range []string{"sdi", "sdi2nd"} {
				dh := dhv1alpha1.GetSampleDH(nm)
				Ω(dh).ShouldNot(BeNil())
				_, err := dhClient.Namespace(nm).Create(ctx, dh, metav1.CreateOptions{})
				Ω(err).NotTo(HaveOccurred())
				Ω(k8sClient.Create(ctx, testroutes.MakeVSystemService(nm))).ShouldNot(HaveOccurred())
				Ω(k8sClient.Create(ctx, testroutes.MakeVSystemCABundleSecret(nm))).ShouldNot(HaveOccurred())
			}
		})

		AfterEach(func() {
			ctx := context.TODO()
			for _, nm := range []string{"sdi", "sdi2nd"} {
				_ = dhClient.Namespace(nm).Delete(ctx, "default", metav1.DeleteOptions{})
				Ω(k8sClient.Delete(ctx, testroutes.MakeVSystemService(nm))).ShouldNot(HaveOccurred())
				Ω(k8sClient.Delete(ctx, testroutes.MakeVSystemCABundleSecret(nm))).ShouldNot(HaveOccurred())
			}
			_ = k8sClient.Delete(ctx, &corev1.Namespace{
				ObjectMeta: metav1.ObjectMeta{Name: "sdi2nd"}})
		})

		It("Should start managing another DH instance", func() {
			ctx := context.Background()
			dh, err := dhClient.Namespace("sdi").Get(ctx, "default", metav1.GetOptions{})
			Ω(err).NotTo(HaveOccurred())
			ωbs.WaitForObserverState(k8sClient, 0, obs,
				func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
					g.Ω(obs.Status.VSystemRoute).To(ωbs.HaveConditionReason("Exposed", metav1.ConditionUnknown, "NotAdmitted"))
					g.Ω(obs).To(ωbs.ReferenceDataHub(dh))
				})

			By("Ensure the route exists only in the currently managed DH namespace")
			var fetched routev1.Route
			Ω(k8sClient.Get(ctx, types.NamespacedName{Namespace: "sdi", Name: "vsystem"}, &fetched)).ShouldNot(HaveOccurred())
			Ω(k8sClient.Get(ctx, types.NamespacedName{Namespace: "sdi2nd", Name: "vsystem"}, &fetched)).Should(HaveOccurred())

			By("Update the SDIObserver instance to manage another DH namespace")
			ωbs.Update(k8sClient, obs, func(obs *sdiv1alpha1.SDIObserver) {
				obs.Spec.SDINamespace = "sdi2nd"
			})

			dh2nd, err := dhClient.Namespace("sdi2nd").Get(ctx, "default", metav1.GetOptions{})
			Ω(err).NotTo(HaveOccurred())

			ωbs.WaitForObserver(k8sClient, obs,
				ωbs.HaveCondition("Ready", ωbs.StatusTrue(), nil),
				ωbs.ReferenceDataHub(dh2nd))

			By("Ensure the route exists in the newly managed DH namespace")
			Ω(k8sClient.Get(ctx, types.NamespacedName{Namespace: "sdi2nd", Name: "vsystem"}, &fetched)).ShouldNot(HaveOccurred())
			// TODO: expect NotFound once we have finalizers
			Ω(k8sClient.Get(ctx, types.NamespacedName{Namespace: "sdi", Name: "vsystem"}, &fetched)).ShouldNot(HaveOccurred())
		})
	})

	Context("When all competing SDIObserver instances are blocked", func() {
		It("Should unblock just one", func() {

		})
	})
})
