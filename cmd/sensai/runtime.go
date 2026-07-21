package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type runtimeMode string

const (
	runtimeSource    runtimeMode = "source"
	runtimeInstalled runtimeMode = "installed"
)

type runtimeLayout struct {
	mode       runtimeMode
	executable string
	sourceRoot string
}

func resolveRuntimeLayout(request string) (runtimeLayout, error) {
	executable, err := resolveExecutable(request)
	if err != nil {
		return runtimeLayout{}, err
	}
	home := platformHome()
	if home != "" && normalizedAbsolutePath(home) && inspectPathComponents(home) == nil {
		installedPath := filepath.Join(home, ".local", "bin", platformExecutableName())
		if executable == installedPath {
			return runtimeLayout{mode: runtimeInstalled, executable: executable}, nil
		}
	}
	if filepath.Base(executable) != platformExecutableName() || filepath.Base(filepath.Dir(executable)) != "bin" {
		return runtimeLayout{}, runtimeExecutableError("unknown_location", nil)
	}
	sourceRoot := filepath.Dir(filepath.Dir(executable))
	if executable != filepath.Join(sourceRoot, "bin", platformExecutableName()) {
		return runtimeLayout{}, runtimeExecutableError("source_executable_mismatch", nil)
	}
	return runtimeLayout{mode: runtimeSource, executable: executable, sourceRoot: sourceRoot}, nil
}

func resolveExecutable(request string) (string, error) {
	if request == "" {
		return "", runtimeExecutableError("path_lookup_failed", nil)
	}
	resolved := request
	pathLookup := !strings.ContainsAny(request, `/\`)
	if pathLookup {
		lookup, err := exec.LookPath(request)
		if err != nil {
			return "", runtimeExecutableError("path_lookup_failed", err)
		}
		resolved = lookup
		if !filepath.IsAbs(resolved) {
			return "", runtimeExecutableError("path_lookup_not_absolute", nil)
		}
	}
	if !filepath.IsAbs(resolved) {
		cwd, err := os.Getwd()
		if err != nil {
			return "", runtimeExecutableError("cwd_unresolved", err)
		}
		resolved = filepath.Join(cwd, resolved)
	}
	for _, component := range strings.FieldsFunc(resolved, func(r rune) bool { return r == '/' || r == '\\' }) {
		if component == ".." {
			return "", runtimeExecutableError("path_not_normalized", nil)
		}
	}
	resolved = filepath.Clean(resolved)
	if !normalizedAbsolutePath(resolved) {
		return "", runtimeExecutableError("path_not_normalized", nil)
	}
	if err := inspectPathComponents(resolved); err != nil {
		return "", runtimeExecutableError("executable_or_parent_link", err)
	}
	info, err := os.Lstat(resolved)
	if err != nil {
		return "", runtimeExecutableError("not_regular_executable", err)
	}
	if err := validatePlatformExecutable(resolved, info); err != nil {
		return "", runtimeExecutableError("not_regular_executable", err)
	}
	parent := filepath.Dir(resolved)
	physicalParent, err := filepath.EvalSymlinks(parent)
	if err != nil {
		return "", runtimeExecutableError("parent_unresolved", err)
	}
	physicalParent, err = filepath.Abs(physicalParent)
	if err != nil || physicalParent != platformCanonicalPath(parent) {
		return "", runtimeExecutableError("parent_not_physical", err)
	}
	return filepath.Join(physicalParent, filepath.Base(resolved)), nil
}

func platformCanonicalPath(path string) string {
	for _, alias := range []string{"/etc", "/tmp", "/var"} {
		physicalAlias, accepted := platformSystemAlias(alias)
		if !accepted {
			continue
		}
		if path == alias {
			return physicalAlias
		}
		if strings.HasPrefix(path, alias+string(filepath.Separator)) {
			return filepath.Join(physicalAlias, strings.TrimPrefix(path, alias+string(filepath.Separator)))
		}
	}
	return path
}

func platformSystemAlias(path string) (string, bool) {
	base := filepath.Base(path)
	if path != filepath.Join(string(filepath.Separator), base) {
		return "", false
	}
	switch base {
	case "etc", "tmp", "var":
	default:
		return "", false
	}
	physical, err := filepath.EvalSymlinks(path)
	if err != nil || physical != filepath.Join(string(filepath.Separator), "private", base) {
		return "", false
	}
	return physical, true
}

func normalizedAbsolutePath(path string) bool {
	if !filepath.IsAbs(path) || path == "" || strings.ContainsAny(path, "\n\t") {
		return false
	}
	if filepath.Clean(path) != path {
		return false
	}
	volume := filepath.VolumeName(path)
	root := volume + string(filepath.Separator)
	return path == root || !strings.HasSuffix(path, string(filepath.Separator))
}

func runtimeExecutableError(detail string, cause error) *commandError {
	if cause == nil {
		cause = errData
	}
	return newCommandError(commandError{
		Exit: exitData, Reason: "runtime.executable_invalid", Detail: detail, Cause: cause,
	})
}

func platformError(operation, path string, cause error) error {
	return fmt.Errorf("%s %s: %w", operation, path, cause)
}

func isPathMissing(err error) bool {
	return errors.Is(err, os.ErrNotExist)
}
