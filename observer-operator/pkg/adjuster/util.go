package adjuster

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/utils/pointer"
)

func adjustOwnerReference(meta *metav1.ObjectMeta, newRef metav1.OwnerReference) {
	orFound := false
	controllerExists := false
	for _, or := range meta.OwnerReferences {
		if or.Name == newRef.Name && or.APIVersion == newRef.APIVersion && or.Kind == newRef.Kind {
			orFound = true
		}
		if or.Controller != nil {
			controllerExists = *or.Controller
		}
	}
	if !orFound {
		ref := newRef
		if controllerExists {
			ref.Controller = pointer.BoolPtr(false)
		}
		meta.OwnerReferences = append(meta.OwnerReferences, ref)
	}
}

func adjustLabels(meta *metav1.ObjectMeta, labels map[string]string) {
	for k, v := range labels {
		if meta.Labels == nil {
			meta.Labels = labels
		} else {
			meta.Labels[k] = v
		}
	}
}

func adjustAnnotations(meta *metav1.ObjectMeta, annotations map[string]string) {
	for k, v := range annotations {
		if meta.Annotations == nil {
			meta.Annotations = annotations
		} else {
			meta.Annotations[k] = v
		}
	}
}
