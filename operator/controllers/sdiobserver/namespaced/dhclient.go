package namespaced

import (
	"context"
	"sort"
	"strings"

	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
)

const (
	DataHubResourceGroup   = "installers.datahub.sap.com"
	DataHubResourceName    = "DataHubs"
	DataHubResourceFull    = "datahubs.installers.datahub.sap.com"
	DataHubResourceVersion = "v1alpha1"
)

func MakeDataHubGVR() schema.GroupVersionResource {
	return schema.GroupVersionResource{
		Group:    DataHubResourceGroup,
		Version:  DataHubResourceVersion,
		Resource: strings.ToLower(DataHubResourceName),
	}
}

type DHClient interface {
	List(ctx context.Context, namespace string) ([]unstructured.Unstructured, error)
	Get(ctx context.Context, namespace string) (*unstructured.Unstructured, error)
}

type dhClient struct {
	client dynamic.Interface
}

func NewDHClient(cfg *rest.Config) (*dhClient, error) {
	// Grab a dynamic interface that we can create informers from
	dc, err := dynamic.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	return &dhClient{client: dc}, nil
}

func (dhc *dhClient) List(ctx context.Context, namespace string) ([]unstructured.Unstructured, error) {
	list, err := dhc.client.Resource(MakeDataHubGVR()).Namespace(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	return list.Items, nil
}

// byDefault moves the default DataHub instance to the front of the list.
// It is a singleton, no other instance is actually expected.
type byDefault []unstructured.Unstructured

func (a byDefault) Len() int      { return len(a) }
func (a byDefault) Swap(i, j int) { a[i], a[j] = a[j], a[i] }
func (a byDefault) Less(i, j int) bool {
	if a[i].GetName() == "default" {
		return true
	}
	if a[j].GetName() == "default" {
		return false
	}
	return a[i].GetName() < a[j].GetName()
}

func (dhc *dhClient) Get(ctx context.Context, namespace string) (*unstructured.Unstructured, error) {
	list, err := dhc.List(ctx, namespace)
	if err != nil {
		return nil, err
	}
	sort.Sort(byDefault(list))
	if len(list) > 0 {
		return &list[0], nil
	}
	return nil, errors.NewNotFound(MakeDataHubGVR().GroupResource(), "default")
}
