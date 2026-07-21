package main

import (
	"errors"
	"fmt"
)

const (
	exitOK          = 0
	exitUsage       = 64
	exitData        = 65
	exitUnavailable = 69
	exitCantCreate  = 73
	exitTemporary   = 75
	exitInterrupted = 130
)

var (
	errUsage       = errors.New("sensai: usage")
	errData        = errors.New("sensai: invalid data")
	errUnavailable = errors.New("sensai: unavailable")
	errCantCreate  = errors.New("sensai: cannot create")
	errTemporary   = errors.New("sensai: temporary failure")
	errInterrupted = errors.New("sensai: interrupted")
)

type commandError struct {
	Exit   int
	Reason string
	Detail string
	Cause  error
	Quiet  bool
}

func (e *commandError) Error() string {
	return fmt.Sprintf("%s: %s", e.Reason, e.Detail)
}

func (e *commandError) Unwrap() error {
	return e.Cause
}

func newCommandError(spec commandError) *commandError {
	return &spec
}

func usageError() *commandError {
	return &commandError{Exit: exitUsage, Reason: "cli.usage", Detail: "invalid_arguments", Cause: errUsage, Quiet: true}
}

func interruptedError(cause error) *commandError {
	return &commandError{Exit: exitInterrupted, Reason: "runtime.interrupted", Detail: "signal", Cause: errors.Join(errInterrupted, cause), Quiet: true}
}
