package sdiobserver

import (
	"fmt"

	"github.com/onsi/gomega/types"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func FailWithStatus(reason metav1.StatusReason) types.GomegaMatcher {
	return &failureStatusMatcher{reason}
}

type failureStatusMatcher struct {
	reason metav1.StatusReason
}

func (m *failureStatusMatcher) Match(actual interface{}) (success bool, err error) {
	if actual == nil {
		return
	}
	if _, ok := actual.(error); !ok {
		return false, fmt.Errorf("expected a kubernetes API Error, not %T", err)
	}
	apierr, ok := actual.(apierrors.APIStatus)
	if !ok {
		return
	}
	if apierr.Status().Reason != m.reason {
		return
	}
	return true, nil
}

func (m *failureStatusMatcher) FailureMessage(actual interface{}) (message string) {
	if actual == nil {
		return fmt.Sprintf("Expected an API Error with reason \"%s\", not a successful execution", m.reason)
	}
	apierr, ok := actual.(apierrors.APIStatus)
	if !ok {
		return fmt.Sprintf("Expected an API Error with reason \"%s\", not an error of type %T and value %#v",
			m.reason, actual, actual)
	}
	if a := apierr.Status().Reason; a != m.reason {
		return fmt.Sprintf("Expected an API Error with reason \"%s\", not \"%s\"", m.reason, a)
	}
	panic("unexpected error")
}

func (m *failureStatusMatcher) NegatedFailureMessage(actual interface{}) (message string) {
	apierr, ok := actual.(apierrors.APIStatus)
	if !ok {
		panic("unexpected error")
	}
	if a := apierr.Status().Reason; a == m.reason {
		return fmt.Sprintf("Expected an API Error with reason other than \"%s\"", m.reason)
	}
	panic("unexpected error")
}
