package namespaced

import (
	"context"
	"strings"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/dynamicinformer"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/source"

	csroute "github.com/openshift/client-go/route/clientset/versioned"
	routeinformers "github.com/openshift/client-go/route/informers/externalversions"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

const (
	//defaultSyncTime = time.Minute
	dhSyncTime    = time.Minute * 3
	routeSyncTime = time.Minute * 10
	coreSyncTime  = time.Minute * 10
)

// Controller manages a single DataHub instance. It is controlled by the SDIObserver resource. The
// controller updates its status. It is created dynamically by the parent controller.
type Controller struct {
	controller.Controller

	mgr                manager.Manager
	unstartedFactories []informerFactory
	cancels            []context.CancelFunc
	// get notified from the parent controller when SDIObserver changes
	chanReconcileObs chan event.GenericEvent
	isStarted        bool
}

var _ controller.Controller = &Controller{}

type informerFactory interface {
	Start(<-chan struct{})
}

// NewController in this context means that the SDIObserver CR is managed by the controller. The controller
// itself is not managed by the manager. It is created dynamically. Usually just for a single DH namespace
// where DataHub instance has been detected.
func NewController(
	client client.Client,
	scheme *runtime.Scheme,
	nmName types.NamespacedName,
	dhNamespace string,
	mgr manager.Manager,
	options controller.Options,
) (*Controller, error) {
	r := &reconciler{
		client:         client,
		scheme:         scheme,
		namespacedName: nmName,
		dhNamespace:    dhNamespace,
	}
	dhClient, err := NewDHClient(mgr.GetConfig())
	if err != nil {
		return nil, err
	}
	r.dhClient = dhClient

	ctrlName := strings.Join([]string{"namespaced", nmName.Namespace, nmName.Name}, "-")
	logger := logf.Log.WithValues(
		"controller name", ctrlName,
		"managed DH namespace", dhNamespace)

	unmanagedCtrl, err := controller.NewUnmanaged(
		ctrlName,
		mgr,
		controller.Options{
			Reconciler: r,
			Log:        logger,
		})
	if err != nil {
		return nil, err
	}

	ctrl := &Controller{
		Controller:       unmanagedCtrl,
		mgr:              mgr,
		chanReconcileObs: make(chan event.GenericEvent),
	}

	obsContext, obsWatchCancel := context.WithCancel(context.Background())
	sc := source.Channel{Source: ctrl.chanReconcileObs}
	if err = sc.InjectStopChannel(obsContext.Done()); err != nil {
		obsWatchCancel()
		return nil, err
	}
	if err := ctrl.Watch(&sc, &handler.EnqueueRequestForObject{}); err != nil {
		obsWatchCancel()
		return nil, err
	}
	ctrl.cancels = append(ctrl.cancels, obsWatchCancel)

	err = ctrl.manageDHNamespace(obsContext, dhNamespace)
	if err != nil {
		obsWatchCancel()
		return nil, err
	}

	return ctrl, nil
}

func (c *Controller) startFactories(chCancel <-chan struct{}) {
	if !c.isStarted {
		// we don't want to miss the intial list of objects produced by each informer once started
		// let's make sure to start the factories once the controller and its queue are prepared
		return
	}
	for _, f := range c.unstartedFactories {
		f.Start(chCancel)
	}
	c.unstartedFactories = nil
}

func (c *Controller) ReconcileObs(obs *sdiv1alpha1.SDIObserver) {
	c.chanReconcileObs <- event.GenericEvent{Object: obs}
}

func (c *Controller) manageDHNamespace(ctx context.Context, dhNamespace string) error {
	cfg := c.mgr.GetConfig()
	kubeClient, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return err
	}
	routesClientSet := csroute.NewForConfigOrDie(cfg)
	dhDynClient := dynamic.NewForConfigOrDie(cfg)
	if err != nil {
		return err
	}

	// Create a factory object that can generate informers for resource types
	c.GetLogger().Info("(*controller).manageDHNamespace: setting up watches for DH instance",
		"DH namespace", dhNamespace)

	// TODO: Watch just metadata
	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(
		dhDynClient,
		dhSyncTime,
		dhNamespace,
		nil)
	informer := factory.ForResource(MakeDataHubGVR())
	c.unstartedFactories = append(c.unstartedFactories, factory)
	if err := c.Watch(
		&source.Informer{Informer: informer.Informer()},
		&handler.EnqueueRequestForObject{}); err != nil {
		return err
	}

	kubeInformerFactory := informers.NewSharedInformerFactoryWithOptions(
		kubeClient,
		coreSyncTime,
		informers.WithNamespace(dhNamespace))
	c.unstartedFactories = append(c.unstartedFactories, kubeInformerFactory)
	lsPred, err := predicate.LabelSelectorPredicate(metav1.LabelSelector{
		MatchLabels: map[string]string{
			"datahub.sap.com/app-component": "vsystem",
			"datahub.sap.com/app":           "vsystem",
		},
	})
	if err != nil {
		return err
	}
	if err := c.Watch(
		&source.Informer{Informer: kubeInformerFactory.Core().V1().Services().Informer()},
		&handler.EnqueueRequestForObject{},
		lsPred); err != nil {
		return err
	}
	if err := c.Watch(
		&source.Informer{Informer: kubeInformerFactory.Core().V1().Secrets().Informer()},
		&handler.EnqueueRequestForObject{},
		predicate.NewPredicateFuncs(func(object client.Object) bool {
			return object.GetName() == vsystemCaBundleSecretName
		})); err != nil {
		return err
	}

	routeInformerFactory := routeinformers.NewSharedInformerFactoryWithOptions(
		routesClientSet,
		routeSyncTime,
		routeinformers.WithNamespace(dhNamespace))
	c.unstartedFactories = append(c.unstartedFactories, routeInformerFactory)
	if err := c.Watch(
		&source.Informer{Informer: routeInformerFactory.Route().V1().Routes().Informer()},
		&handler.EnqueueRequestForObject{}); err != nil {
		return err
	}

	c.startFactories(ctx.Done())
	return nil
}

func (c *Controller) Start(ctx context.Context) error {
	childContext, cancel := context.WithCancel(context.Background())
	go func() {
		if err := c.Controller.Start(childContext); err != nil {
			c.GetLogger().Error(err, "(*controller).Start: controller terminated")
		}
	}()

	c.isStarted = true
	c.startFactories(childContext.Done())
	c.cancels = append(c.cancels, cancel)
	return nil
}

func (c *Controller) Stop() {
	close(c.chanReconcileObs)
	for _, c := range c.cancels {
		c()
	}
}
