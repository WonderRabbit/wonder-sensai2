//go:build windows

package main

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const moveFileReplaceExisting = 0x1

var moveFileExW = syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")

func platformExecutableName() string {
	return "sensai.exe"
}

func platformExecutableTempPattern() string {
	return executableTempPattern(platformExecutableName())
}

func platformHome() string {
	return os.Getenv("USERPROFILE")
}

func inspectPathComponents(path string) error {
	if !filepath.IsAbs(path) {
		return platformError("inspect", path, errors.New("path is not absolute"))
	}
	volume := filepath.VolumeName(path)
	current := volume + string(filepath.Separator)
	remainder := strings.TrimPrefix(path, volume)
	remainder = strings.TrimPrefix(remainder, string(filepath.Separator))
	for _, component := range strings.Split(remainder, string(filepath.Separator)) {
		if component == "" {
			continue
		}
		current = filepath.Join(current, component)
		name, err := syscall.UTF16PtrFromString(current)
		if err != nil {
			return platformError("encode path", current, err)
		}
		attributes, err := syscall.GetFileAttributes(name)
		if isPathMissing(err) {
			return nil
		}
		if err != nil {
			return platformError("attributes", current, err)
		}
		if attributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			return platformError("inspect", current, errors.New("reparse point rejected"))
		}
	}
	return nil
}

func validatePlatformExecutable(path string, info fs.FileInfo) error {
	if !info.Mode().IsRegular() || !strings.EqualFold(filepath.Ext(path), ".exe") {
		return platformError("validate executable", path, errors.New("regular .exe required"))
	}
	return nil
}

func preparePlatformExecutable(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return platformError("lstat", path, err)
	}
	return validatePlatformExecutable(path, info)
}

func publishNoReplace(source, destination string) error {
	return moveFile(source, destination, 0)
}

func publishDirectoryNoReplace(source, destination string) error {
	return moveFile(source, destination, 0)
}

func replaceAtomic(source, destination string) error {
	return moveFile(source, destination, moveFileReplaceExisting)
}

func moveFile(source, destination string, flags uint32) error {
	from, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return platformError("encode source", source, err)
	}
	to, err := syscall.UTF16PtrFromString(destination)
	if err != nil {
		return platformError("encode destination", destination, err)
	}
	result, _, callErr := moveFileExW.Call(
		uintptr(unsafe.Pointer(from)),
		uintptr(unsafe.Pointer(to)),
		uintptr(flags),
	)
	if result == 0 {
		return platformError("replace", destination, callErr)
	}
	return nil
}
