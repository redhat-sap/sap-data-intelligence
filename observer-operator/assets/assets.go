package assets

import (
	"embed"

	routev1 "github.com/openshift/api/route/v1"

	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
)

var (
	//go:embed manifests/*
	manifests embed.FS

	appsScheme = runtime.NewScheme()
	appsCodecs = serializer.NewCodecFactory(appsScheme)
)

func init() {
	if err := routev1.AddToScheme(appsScheme); err != nil {
		panic(err)
	}
}

func GetRouteFromFile(name string) *routev1.Route {
	routeBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	routeObject, err := runtime.Decode(appsCodecs.UniversalDecoder(routev1.SchemeGroupVersion), routeBytes)
	if err != nil {
		panic(err)
	}

	return routeObject.(*routev1.Route)
}
