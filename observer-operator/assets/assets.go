package assets

import (
	"embed"

	routev1 "github.com/openshift/api/route/v1"
	configv1 "github.com/openshift/machine-config-operator/pkg/apis/machineconfiguration.openshift.io/v1"

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

func GetMachineConfigFromFile(name string) *configv1.MachineConfig {
	machineConfigBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	machineConfigObject, err := runtime.Decode(appsCodecs.UniversalDecoder(configv1.SchemeGroupVersion), machineConfigBytes)
	if err != nil {
		panic(err)
	}

	return machineConfigObject.(*configv1.MachineConfig)
}

func GetContainerRuntimeConfigFromFile(name string) *configv1.ContainerRuntimeConfig {
	containerRuntimeConfigBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	containerRuntimeConfigObject, err := runtime.Decode(appsCodecs.UniversalDecoder(configv1.SchemeGroupVersion), containerRuntimeConfigBytes)
	if err != nil {
		panic(err)
	}

	return containerRuntimeConfigObject.(*configv1.ContainerRuntimeConfig)
}
