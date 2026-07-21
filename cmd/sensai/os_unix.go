//go:build !windows

package main

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func platformExecutableName() string {
	return "sensai"
}

func platformExecutableTempPattern() string {
	return executableTempPattern(platformExecutableName())
}

func platformHome() string {
	return os.Getenv("HOME")
}

func inspectPathComponents(path string) error {
	if !filepath.IsAbs(path) {
		return platformError("inspect", path, errors.New("path is not absolute"))
	}
	current := string(filepath.Separator)
	for _, component := range strings.Split(strings.TrimPrefix(path, current), string(filepath.Separator)) {
		if component == "" {
			continue
		}
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if isPathMissing(err) {
			return nil
		}
		if err != nil {
			return platformError("lstat", current, err)
		}
		if info.Mode()&fs.ModeSymlink != 0 {
			physicalAlias, accepted := platformSystemAlias(current)
			if !accepted {
				return platformError("inspect", current, errors.New("symlink rejected"))
			}
			current = physicalAlias
		}
	}
	return nil
}

func validatePlatformExecutable(path string, info fs.FileInfo) error {
	if !info.Mode().IsRegular() || info.Mode()&0111 == 0 {
		return platformError("validate executable", path, errors.New("regular executable required"))
	}
	return nil
}

func preparePlatformExecutable(path string) error {
	if err := os.Chmod(path, 0755); err != nil {
		return platformError("chmod", path, err)
	}
	return nil
}

func publishNoReplace(source, destination string) error {
	if err := os.Link(source, destination); err != nil {
		return platformError("link", destination, err)
	}
	if err := os.Remove(source); err != nil {
		return platformError("remove published source", source, err)
	}
	return nil
}

func replaceAtomic(source, destination string) error {
	if err := os.Rename(source, destination); err != nil {
		return platformError("rename", destination, err)
	}
	return nil
}
