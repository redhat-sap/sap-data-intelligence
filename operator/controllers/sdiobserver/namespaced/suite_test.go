package namespaced_test

import (
	"context"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"go.uber.org/zap/zapcore"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	"sigs.k8s.io/controller-runtime/pkg/envtest/printer"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	routev1 "github.com/openshift/api/route/v1"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
	. "github.com/redhat-sap/sap-data-intelligence/operator/controllers/sdiobserver/namespaced"
	dhv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/test/datahub/api/v1alpha1"
	//+kubebuilder:scaffold:imports
)

// These tests use Ginkgo (BDD-style Go testing framework). Refer to
// http://onsi.github.io/ginkgo/ to learn more about Ginkgo.

//var cfg *rest.Config
var k8sClient client.Client
var k8sManager ctrl.Manager
var testEnv *envtest.Environment
var nmCtrl *Controller

// need to use the k8sClient throughout the tests instead of OpenShift client
//var routeClient csroutev1.RouteV1Interface
var mgrCancel context.CancelFunc

//var dhClient dynamic.NamespaceableResourceInterface

func TestAPIs(t *testing.T) {
	RegisterFailHandler(Fail)

	RunSpecsWithDefaultAndCustomReporters(t,
		"Controller Suite",
		[]Reporter{printer.NewlineReporter{}})
}

var _ = BeforeSuite(func() {
	logf.SetLogger(zap.New(
		zap.WriteTo(GinkgoWriter),
		zap.UseDevMode(true),
		zap.Level(zapcore.Level(-4))),
	)

	By("bootstrapping test environment")
	testEnv = &envtest.Environment{
		CRDDirectoryPaths: []string{
			filepath.Join("..", "..", "..", "config", "crd", "bases"),
			filepath.Join("..", "..", "..", "test", "config", "crd", "bases"),
		},
		ErrorIfCRDPathMissing: true,
	}

	cfg, err := testEnv.Start()
	Expect(err).NotTo(HaveOccurred())
	Expect(cfg).NotTo(BeNil())

	err = sdiv1alpha1.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())
	Expect(dhv1alpha1.AddToScheme(scheme.Scheme)).NotTo(HaveOccurred())
	Expect(routev1.Install(scheme.Scheme)).NotTo(HaveOccurred())

	//+kubebuilder:scaffold:scheme

	k8sClient, err = client.New(cfg, client.Options{Scheme: scheme.Scheme})
	Expect(err).NotTo(HaveOccurred())
	Expect(k8sClient).NotTo(BeNil())

	k8sManager, err = ctrl.NewManager(cfg, ctrl.Options{
		Scheme: scheme.Scheme,
		Logger: logf.Log,
	})
	Expect(err).ToNot(HaveOccurred())

	//routeClient = csroute.NewForConfigOrDie(cfg).RouteV1()
	dynClient := dynamic.NewForConfigOrDie(cfg)
	dhClient := dynClient.Resource(MakeDataHubGVR())

	for _, nm := range []string{"sdi", "sdi-observer"} {
		Expect(k8sClient.Create(context.TODO(), &corev1.Namespace{
			ObjectMeta: metav1.ObjectMeta{
				Name: nm,
			},
		})).ToNot(HaveOccurred())
	}

	nmCtrl, err = NewController(
		k8sClient,
		scheme.Scheme,
		types.NamespacedName{
			Namespace: "sdi-observer",
			Name:      "sdi",
		},
		"sdi",
		k8sManager,
		controller.Options{},
	)
	Expect(err).NotTo(HaveOccurred())

	dh := dhv1alpha1.GetSampleDH("sdi")
	Expect(dh).ShouldNot(BeNil())
	_, err = dhClient.Namespace("sdi").Create(context.TODO(), dh, metav1.CreateOptions{})
	Expect(err).NotTo(HaveOccurred())

	var ctx context.Context
	ctx, mgrCancel = context.WithCancel(context.Background())
	go func() {
		defer GinkgoRecover()
		err = k8sManager.Start(ctx)
		Expect(err).ToNot(HaveOccurred(), "failed to run manager")
	}()

	Expect(nmCtrl.Start(ctx)).NotTo(HaveOccurred())
}, 60)

var _ = AfterSuite(func() {
	By("tearing down the test environment")
	if nmCtrl != nil {
		nmCtrl.Stop()
	}
	if mgrCancel != nil {
		mgrCancel()
	}
	err := testEnv.Stop()
	Expect(err).NotTo(HaveOccurred())
})
