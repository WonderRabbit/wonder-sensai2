package main

import (
	"context"
	"errors"
	"fmt"
	"io"
)

const usageText = `사용법:
  ./bin/sensai help
  ./bin/sensai doctor tools
  ./bin/sensai doctor models
  ./bin/sensai stage <absent-absolute-target>
  ./bin/sensai install
  ./bin/sensai mission init <mission-id> <target-relative-path> <goal>
  ./bin/sensai mission checkpoint <mission-id> <candidate-progress.json> <expected-revision> <expected-sha256>
  ./bin/sensai mission status <mission-id>
  ./bin/sensai mission resume <mission-id> [<expected-revision> <expected-sha256>]

종료 코드:
  0   성공
  64  사용법 오류
  65  입력·설정·제품 식별 오류
  69  필수 도구 또는 transport 사용 불가
  73  stage 대상 생성 불가 또는 install managed 충돌
  75  잠금·revision·hash 충돌로 나중에 다시 시도해야 함

이 CLI는 도구를 설치하거나 자격증명을 읽거나 모델을 호출하지 않는다.
`

type cli struct {
	ctx     context.Context
	runtime runtimeLayout
	stdout  io.Writer
	stderr  io.Writer
}

type invocation struct {
	ctx        context.Context
	args       []string
	executable string
	stdout     io.Writer
	stderr     io.Writer
}

func runInvocation(call invocation) int {
	layout, err := resolveRuntimeLayout(call.executable)
	if err == nil {
		app := cli{ctx: call.ctx, runtime: layout, stdout: call.stdout, stderr: call.stderr}
		err = app.dispatch(call.args)
	}
	if err == nil {
		return exitOK
	}
	var cliErr *commandError
	if !errors.As(err, &cliErr) {
		cliErr = newCommandError(commandError{
			Exit: exitUnavailable, Reason: "runtime.unexpected", Detail: "internal_error", Cause: err,
		})
	}
	if cliErr.Exit == exitInterrupted {
		return cliErr.Exit
	}
	if cliErr.Exit == exitUsage {
		if _, writeErr := io.WriteString(call.stderr, usageText); writeErr != nil {
			return exitUnavailable
		}
	} else if !cliErr.Quiet {
		if _, writeErr := fmt.Fprintf(call.stderr, "오류 reason=%s detail=%s\n", cliErr.Reason, cliErr.Detail); writeErr != nil {
			return exitUnavailable
		}
	}
	return cliErr.Exit
}

func (c cli) dispatch(args []string) error {
	if len(args) == 0 {
		return usageError()
	}
	switch args[0] {
	case "help", "-h", "--help":
		if len(args) != 1 {
			return usageError()
		}
		_, err := io.WriteString(c.stdout, usageText)
		if err != nil {
			return newCommandError(commandError{
				Exit: exitUnavailable, Reason: "runtime.output_failed", Detail: "help", Cause: err,
			})
		}
		return nil
	case "doctor":
		return c.dispatchDoctor(args[1:])
	case "stage":
		if len(args) != 2 {
			return usageError()
		}
		return c.stage(args[1])
	case "install":
		if len(args) != 1 {
			return usageError()
		}
		return c.install()
	case "mission":
		return c.dispatchMission(args[1:])
	default:
		return usageError()
	}
}

func (c cli) dispatchDoctor(args []string) error {
	if len(args) != 1 {
		return usageError()
	}
	switch args[0] {
	case "tools":
		return c.doctorTools()
	case "models":
		return c.doctorModels()
	default:
		return usageError()
	}
}

func (c cli) dispatchMission(args []string) error {
	if len(args) == 0 {
		return usageError()
	}
	switch args[0] {
	case "init":
		if len(args) != 4 {
			return usageError()
		}
		return c.missionInit(args[1], args[2], args[3])
	case "checkpoint":
		if len(args) != 5 {
			return usageError()
		}
		return c.missionCheckpoint(args[1], args[2], args[3], args[4])
	case "status":
		if len(args) != 2 {
			return usageError()
		}
		return c.missionStatus(args[1])
	case "resume":
		if len(args) == 2 {
			return c.missionResume(args[1], "", "")
		}
		if len(args) == 4 {
			return c.missionResume(args[1], args[2], args[3])
		}
		return usageError()
	default:
		return usageError()
	}
}
