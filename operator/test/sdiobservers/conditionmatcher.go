package sdiobservers

import (
	"fmt"
	"strings"

	"github.com/onsi/gomega/types"

	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	sdiv1alpha1 "github.com/redhat-sap/sap-data-intelligence/operator/api/v1alpha1"
)

func StatusTrue() *metav1.ConditionStatus {
	r := metav1.ConditionTrue
	return &r
}
func StatusFalse() *metav1.ConditionStatus {
	r := metav1.ConditionFalse
	return &r
}
func StatusUnknown() *metav1.ConditionStatus {
	r := metav1.ConditionUnknown
	return &r
}

func HaveCondition(cType string, status *metav1.ConditionStatus, reason *string) types.GomegaMatcher {
	return &conditionMatcher{cType, status, reason}
}

func HaveConditionStatus(cType string, status metav1.ConditionStatus) types.GomegaMatcher {
	return &conditionMatcher{cType: cType, status: &status}
}

func HaveConditionReason(cType string, status metav1.ConditionStatus, reason string) types.GomegaMatcher {
	return &conditionMatcher{cType: cType, status: &status, reason: &reason}
}

type conditionMatcher struct {
	cType  string
	status *metav1.ConditionStatus
	reason *string
}

func getConditions(actual interface{}) ([]metav1.Condition, error) {
	var conditions []metav1.Condition
	switch t := actual.(type) {
	case sdiv1alpha1.SDIObserver:
		conditions = t.Status.Conditions
	case *sdiv1alpha1.SDIObserver:
		conditions = t.Status.Conditions
	case sdiv1alpha1.ManagedRouteStatus:
		conditions = t.Conditions
	case *sdiv1alpha1.ManagedRouteStatus:
		conditions = t.Conditions
	default:
		return nil, fmt.Errorf("conditionMatcher expects SDIObserver or ManagedRouteStatus, not %T", t)
	}
	return conditions, nil
}

func (m *conditionMatcher) Match(actual interface{}) (success bool, err error) {
	var conditions []metav1.Condition
	conditions, err = getConditions(actual)
	if err != nil {
		return
	}

	c := meta.FindStatusCondition(conditions, m.cType)
	if c == nil {
		return
	}
	if m.status != nil && *m.status != c.Status {
		return
	}
	if m.reason != nil && *m.reason != c.Reason {
		return
	}
	return true, nil
}

func (m *conditionMatcher) FailureMessage(actual interface{}) (message string) {
	conditions, err := getConditions(actual)
	if err != nil {
		return err.Error()
	}

	c := meta.FindStatusCondition(conditions, m.cType)
	if c == nil {
		types := make([]string, 0, len(conditions))
		for _, condition := range conditions {
			types = append(types, condition.Type)
		}
		return fmt.Sprintf("Expected condition type \"%s\" not found among: %s", m.cType, strings.Join(types, ","))
	}
	var errs []string
	if m.status != nil && *m.status != c.Status {
		errs = append(errs, fmt.Sprintf("condition[type=%s].Status=\"%s\" to be \"%s\"", m.cType, c.Status, *m.status))
	}
	if m.reason != nil && *m.reason != c.Reason {
		errs = append(errs, fmt.Sprintf("condition[type=%s].Reason=\"%s\" to be \"%s\"", m.cType, c.Reason, *m.reason))
	}
	if len(errs) == 0 {
		panic("unexpected error")
	}
	return fmt.Sprintf("Expected %s", strings.Join(errs, " AND "))
}

func (m *conditionMatcher) NegatedFailureMessage(actual interface{}) (message string) {
	conditions, err := getConditions(actual)
	if err != nil {
		return fmt.Sprintf("%v", err)
	}

	c := meta.FindStatusCondition(conditions, m.cType)
	if c == nil {
		panic("should contain the condition type")
	}
	if m.status == nil && m.reason == nil {
		types := make([]string, 0, len(conditions))
		for _, condition := range conditions {
			types = append(types, condition.Type)
		}
		return fmt.Sprintf("Expected condition[type=%s] not to be present among: %s",
			m.cType, strings.Join(types, ","))
	}
	var errs []string
	if m.status != nil && *m.status == c.Status {
		errs = append(errs, fmt.Sprintf("condition[type=%s].Status=\"%s\" not to be \"%s\"", m.cType, c.Status, *m.status))
	}
	if m.reason != nil && *m.reason != c.Reason {
		errs = append(errs, fmt.Sprintf("condition[type=%s].Reason=\"%s\" not to be \"%s\"", m.cType, c.Reason, *m.reason))
	}
	if len(errs) == 0 {
		panic("unexpected error")
	}
	if len(errs) == 1 {
		return fmt.Sprintf("Expected %s", errs[0])
	}
	for i := 0; i < len(errs); i++ {
		errs[i] = strings.Replace(errs[i], " not to be ", " to be ", 1)
	}
	return fmt.Sprintf("Expected neither %s", strings.Join(errs, " NOR "))
}
