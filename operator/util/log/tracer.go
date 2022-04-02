// Package log contains utilities for tracing functions.
package log

import (
	"fmt"
	"path"
	"runtime"

	"github.com/go-logr/logr"
)

const (
	unknownFunctionName = "unknown function"
	traceLevelIncrement = 3
)

// Tracer wraps the standard logr.Logger. It is supposed to be used in a scope of a single funtion. Its main
// purpose is to add a caller's function name to the beggining of the log message, log the beggining and end
// of the function.  It shall be initialized at the beginning of the function block like this:
//
// 		tracer := λ.Tracer(log.FromContext(ctx))
//      defer λ.Leave(tracer)
//
// Unless the tracer is used anywhere else in the function, the statements can be squashed to a single line:
//
// 		defer λ.Leave(λ.Tracer(log.FromContext(ctx)))
type Tracer struct {
	logr.Logger
	funcName *string
}

// Enter creates a Tracer and logs a function entry message.
func Enter(logger logr.Logger, keyAndValues ...interface{}) Tracer {
	l := logger.V(traceLevelIncrement)
	t := Tracer{Logger: logger}
	if !l.Enabled() {
		return t
	}
	pc, _, _, ok := runtime.Caller(1)
	name := unknownFunctionName
	if ok {
		f := runtime.FuncForPC(pc)
		_, name = path.Split(f.Name())
		t.funcName = &name
	}
	l.Info(fmt.Sprintf("%s: entered", name), keyAndValues...)
	return t
}

// Leave is a call that should be deferred to the end of function call. It logs the function's exit.
func Leave(t Tracer) {
	t.V(traceLevelIncrement).Info("leaving")
}

func (t Tracer) V(i int) Tracer {
	return Tracer{Logger: t.Logger.V(i), funcName: t.funcName}
}

func (t Tracer) Info(msg string, keyAndValues ...interface{}) {
	name := unknownFunctionName
	if t.funcName != nil {
		name = *t.funcName
	}
	t.Logger.Info(fmt.Sprintf("%s: %s", name, msg), keyAndValues...)
}
