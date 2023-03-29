package assets

import (
	"embed"
	openshiftv1 "github.com/openshift/api/image/v1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"

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

func GetKubeletConfigFromFile(name string) *configv1.KubeletConfig {
	kubeletConfigBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	kubeletConfigObject, err := runtime.Decode(appsCodecs.UniversalDecoder(configv1.SchemeGroupVersion), kubeletConfigBytes)
	if err != nil {
		panic(err)
	}

	return kubeletConfigObject.(*configv1.KubeletConfig)
}

func GetMachineConfigPoolFromFile(name string) *configv1.MachineConfigPool {
	machineConfigPoolBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	machineConfigPoolObject, err := runtime.Decode(appsCodecs.UniversalDecoder(configv1.SchemeGroupVersion), machineConfigPoolBytes)
	if err != nil {
		panic(err)
	}

	return machineConfigPoolObject.(*configv1.MachineConfigPool)
}

func GetDaemonSetFromFile(name string) *appsv1.DaemonSet {
	daemonSetBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	daemonSetObject, err := runtime.Decode(appsCodecs.UniversalDecoder(appsv1.SchemeGroupVersion), daemonSetBytes)
	if err != nil {
		panic(err)
	}

	return daemonSetObject.(*appsv1.DaemonSet)
}

func GetImageStreamFromFile(name string) *openshiftv1.ImageStream {
	imageStreamBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	imageStreamObject, err := runtime.Decode(appsCodecs.UniversalDecoder(openshiftv1.SchemeGroupVersion), imageStreamBytes)
	if err != nil {
		panic(err)
	}

	return imageStreamObject.(*openshiftv1.ImageStream)
}

func GetServiceAccountFromFile(name string) *corev1.ServiceAccount {
	serviceAccountBytes, err := manifests.ReadFile(name)
	if err != nil {
		panic(err)
	}

	serviceAccountObject, err := runtime.Decode(appsCodecs.UniversalDecoder(corev1.SchemeGroupVersion), serviceAccountBytes)
	if err != nil {
		panic(err)
	}

	return serviceAccountObject.(*corev1.ServiceAccount)
}
