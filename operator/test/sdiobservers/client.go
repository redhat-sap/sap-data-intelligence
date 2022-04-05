package sdiobservers

import (
	"context"
	"time"

	"k8s.io/client-go/util/retry"

	. "github.com/onsi/gomega"
	ωtypes "github.com/onsi/gomega/types"

	"sigs.k8s.io/controller-runtime/pkg/client"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

const (
	timeout = time.Second * 5
	//duration = time.Second * 10
	interval = time.Millisecond * 100
)

func WaitForObserverState(
	k8sClient client.Client,
	offset int,
	obs *sdiv1alpha1.SDIObserver,
	assert func(g Gomega, obs *sdiv1alpha1.SDIObserver),
) *sdiv1alpha1.SDIObserver {
	var ctx = context.TODO()
	EventuallyWithOffset(offset+1, func(g Gomega) {
		g.Ω(k8sClient.Get(ctx, client.ObjectKeyFromObject(obs), obs)).ToNot(HaveOccurred())
		assert(g, obs)
	}, timeout, interval).Should(Succeed())
	return obs
}

func WaitForObserver(
	k8sClient client.Client,
	obs *sdiv1alpha1.SDIObserver,
	matchers ...ωtypes.GomegaMatcher,
) *sdiv1alpha1.SDIObserver {
	return WaitForObserverState(k8sClient, 1, obs, func(g Gomega, obs *sdiv1alpha1.SDIObserver) {
		for _, m := range matchers {
			g.Ω(obs).WithOffset(1).To(m)
		}
	})
}

func Update(
	k8sClient client.Client,
	obs *sdiv1alpha1.SDIObserver,
	update func(obs *sdiv1alpha1.SDIObserver),
) {
	ctx := context.TODO()
	Expect(retry.RetryOnConflict(retry.DefaultRetry, func() error {
		Ω(k8sClient.Get(ctx, client.ObjectKeyFromObject(obs), obs)).ToNot(HaveOccurred())
		update(obs)
		return k8sClient.Update(ctx, obs)
	})).NotTo(HaveOccurred())
}

func UpdateStatus(
	k8sClient client.Client,
	obs *sdiv1alpha1.SDIObserver,
	update func(obs *sdiv1alpha1.SDIObserver),
) {
	ctx := context.TODO()
	Expect(retry.RetryOnConflict(retry.DefaultRetry, func() error {
		Ω(k8sClient.Get(ctx, client.ObjectKeyFromObject(obs), obs)).ToNot(HaveOccurred())
		update(obs)
		return k8sClient.Status().Update(ctx, obs)
	})).NotTo(HaveOccurred())
}
