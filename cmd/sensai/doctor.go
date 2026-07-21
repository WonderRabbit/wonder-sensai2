package main

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

type doctorTool struct {
	name    string
	product string
	valid   func(string) bool
}

var semanticVersion = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)

var doctorTools = []doctorTool{
	{name: "opencode", product: "OpenCode", valid: func(version string) bool { return version == "1.18.3" }},
	{name: "fd", product: "fd", valid: func(version string) bool { return strings.HasPrefix(version, "fd ") }},
	{name: "rg", product: "ripgrep", valid: func(version string) bool { return strings.HasPrefix(version, "ripgrep ") }},
	{name: "sg", product: "ast-grep", valid: func(version string) bool { return strings.HasPrefix(version, "ast-grep ") }},
	{name: "jq", product: "jq", valid: func(version string) bool { return strings.HasPrefix(version, "jq-") }},
	{name: "yq", product: "MikeFarah-yq", valid: func(version string) bool {
		return strings.Contains(version, "github.com/mikefarah/yq")
	}},
	{name: "mdq", product: "mdq", valid: func(version string) bool { return strings.HasPrefix(version, "mdq ") }},
	{name: "mmdc", product: "mermaid-cli", valid: semanticVersion.MatchString},
}

func (c cli) doctorTools() error {
	resultExit := exitOK
	for _, tool := range doctorTools {
		path, err := exec.LookPath(tool.name)
		if err != nil {
			if _, writeErr := fmt.Fprintf(c.stderr, "도구 tool=%s status=UNAVAILABLE reason=tool.unavailable\n", tool.name); writeErr != nil {
				return newCommandError(commandError{
					Exit: exitUnavailable, Reason: "runtime.output_failed", Detail: "doctor_tools", Cause: writeErr,
				})
			}
			resultExit = exitUnavailable
			continue
		}
		command := exec.CommandContext(c.ctx, path, "--version")
		output, commandErr := command.CombinedOutput()
		if c.ctx.Err() != nil {
			return interruptedError(c.ctx.Err())
		}
		version := firstLine(string(output))
		if commandErr != nil || !tool.valid(version) {
			if _, writeErr := fmt.Fprintf(c.stderr, "도구 tool=%s status=INVALID reason=tool.identity_mismatch\n", tool.name); writeErr != nil {
				return newCommandError(commandError{
					Exit: exitUnavailable, Reason: "runtime.output_failed", Detail: "doctor_tools", Cause: writeErr,
				})
			}
			if resultExit != exitUnavailable {
				resultExit = exitData
			}
			continue
		}
		if _, err := fmt.Fprintf(c.stdout, "도구 tool=%s status=READY product=%s version=%s\n", tool.name, tool.product, version); err != nil {
			return newCommandError(commandError{
				Exit: exitUnavailable, Reason: "runtime.output_failed", Detail: "doctor_tools", Cause: err,
			})
		}
	}
	if resultExit == exitOK {
		return nil
	}
	cause := errData
	if resultExit == exitUnavailable {
		cause = errUnavailable
	}
	return &commandError{Exit: resultExit, Reason: "doctor.tools_failed", Detail: "probe", Cause: cause, Quiet: true}
}

func firstLine(output string) string {
	line, _, _ := strings.Cut(strings.ReplaceAll(output, "\r\n", "\n"), "\n")
	return strings.TrimSuffix(line, "\r")
}
