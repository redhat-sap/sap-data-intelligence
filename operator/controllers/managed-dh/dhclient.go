package managed_dh

import (
	"context"
	"strings"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/dynamicinformer"
	"k8s.io/client-go/informers"
	ctrl "sigs.k8s.io/controller-runtime"
)

const (
	DataHubResourceGroup   = "installers.datahub.sap.com"
	DataHubResourceName    = "DataHubs"
	DataHubResourceFull    = "datahubs.installers.datahub.sap.com"
	DataHubResourceVersion = "v1alpha1"
)

func MkDataHubGvr() schema.GroupVersionResource {
	return schema.GroupVersionResource{
		Group:    DataHubResourceGroup,
		Version:  DataHubResourceVersion,
		Resource: strings.ToLower(DataHubResourceName),
	}
}

func GetDynamicInformer(resourceType string, namespace string) (informers.GenericInformer, error) {
	cfg := ctrl.GetConfigOrDie()

	// Grab a dynamic interface that we can create informers from
	dc, err := dynamic.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	// Create a factory object that can generate informers for resource types
	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(dc, 0, namespace, nil)
	// "GroupVersionResource" to say what to watch e.g. "deployments.v1.apps" or "seldondeployments.v1.machinelearning.seldon.io"
	gvr, _ := schema.ParseResourceArg(resourceType)
	// Finally, create our informer for deployments!
	informer := factory.ForResource(*gvr)
	return informer, nil
}

type DhClient struct {
	client dynamic.Interface
}

func NewDhClient() (*DhClient, error) {
	cfg := ctrl.GetConfigOrDie()

	// Grab a dynamic interface that we can create informers from
	dc, err := dynamic.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	return &DhClient{client: dc}, nil
}

func (dhc *DhClient) List(ctx context.Context, namespace string) ([]unstructured.Unstructured, error) {
	list, err := dhc.client.Resource(MkDataHubGvr()).Namespace(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	return list.Items, nil
}
