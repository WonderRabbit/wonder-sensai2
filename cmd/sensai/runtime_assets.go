package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type assetProvenance string

const (
	provenanceProject assetProvenance = "project"
	provenanceGlobal  assetProvenance = "global"
)

type resolvedAsset struct {
	path       string
	provenance assetProvenance
}

type globalAssets struct {
	root          string
	opencode      string
	toolchainLock string
}

type missionAssets struct {
	global         globalAssets
	traceSchema    resolvedAsset
	progressSchema resolvedAsset
	traceRecipe    resolvedAsset
	progressRecipe resolvedAsset
}

func resolveGlobalAssets() (globalAssets, error) {
	root, err := resolveConfigRoot()
	if err != nil {
		return globalAssets{}, err
	}
	opencodePath, present, err := resolveRegularAsset(root, "opencode.json", false)
	if err != nil || !present {
		return globalAssets{}, err
	}
	if err := requireJSONPath(opencodePath, "opencode.json"); err != nil {
		return globalAssets{}, err
	}
	lockPath, present, err := resolveRegularAsset(root, "toolchain.lock.json", false)
	if err != nil || !present {
		return globalAssets{}, err
	}
	if err := requireJSONPath(lockPath, "toolchain.lock.json"); err != nil {
		return globalAssets{}, err
	}
	return globalAssets{root: root, opencode: opencodePath, toolchainLock: lockPath}, nil
}

func resolveConfigRoot() (string, error) {
	root := os.Getenv("OPENCODE_CONFIG_DIR")
	if root == "" {
		if xdg := os.Getenv("XDG_CONFIG_HOME"); xdg != "" {
			root = filepath.Join(xdg, "opencode")
		} else {
			home := platformHome()
			if home == "" {
				return "", assetError("runtime.asset_invalid", "home", nil)
			}
			root = filepath.Join(home, ".config", "opencode")
		}
	}
	if !normalizedAbsolutePath(root) {
		return "", assetError("runtime.asset_invalid", "config_root_not_absolute", nil)
	}
	if err := inspectPathComponents(root); err != nil {
		return "", assetError("runtime.asset_invalid", "config_root_symlink", err)
	}
	info, err := os.Lstat(root)
	if isPathMissing(err) {
		return root, nil
	}
	if err != nil {
		return "", assetError("runtime.asset_invalid", "config_root_unresolved", err)
	}
	if !info.IsDir() {
		return "", assetError("runtime.asset_invalid", "config_root_not_directory", nil)
	}
	physical, err := filepath.EvalSymlinks(root)
	if err != nil || physical != root {
		return "", assetError("runtime.asset_invalid", "config_root_not_physical", err)
	}
	return root, nil
}

func resolveRegularAsset(root, relative string, optional bool) (string, bool, error) {
	if err := safeAssetRelativePath(relative); err != nil {
		return "", false, assetError("runtime.asset_invalid", "unsafe_asset_path", err)
	}
	if err := inspectPathComponents(root); err != nil {
		return "", false, assetError("runtime.asset_invalid", relative, err)
	}
	rootInfo, err := os.Lstat(root)
	if isPathMissing(err) && optional {
		return "", false, nil
	}
	if isPathMissing(err) {
		return "", false, assetError("runtime.asset_missing", relative, err)
	}
	if err != nil || !rootInfo.IsDir() {
		return "", false, assetError("runtime.asset_invalid", relative, err)
	}
	path := filepath.Join(root, filepath.FromSlash(relative))
	if err := inspectPathComponents(path); err != nil {
		return "", false, assetError("runtime.asset_invalid", relative, err)
	}
	info, err := os.Lstat(path)
	if isPathMissing(err) && optional {
		return "", false, nil
	}
	if isPathMissing(err) {
		return "", false, assetError("runtime.asset_missing", relative, err)
	}
	if err != nil || !info.Mode().IsRegular() {
		return "", false, assetError("runtime.asset_invalid", relative, err)
	}
	return path, true, nil
}

func safeAssetRelativePath(relative string) error {
	if relative == "" || filepath.IsAbs(relative) || strings.Contains(relative, "\\") ||
		strings.HasPrefix(relative, "#") || strings.IndexFunc(relative, func(character rune) bool {
		return character < 0x20 || character == 0x7f
	}) >= 0 {
		return errors.New("asset path must be non-empty slash-relative")
	}
	for _, component := range strings.Split(relative, "/") {
		if component == "" || component == "." || component == ".." {
			return errors.New("unsafe asset component")
		}
	}
	return nil
}

func requireJSONPath(path, detail string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return assetError("runtime.asset_invalid", detail, err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	var document json.RawMessage
	if err := decoder.Decode(&document); err != nil {
		return assetError("runtime.asset_invalid", detail, err)
	}
	if err := decoder.Decode(new(json.RawMessage)); !errors.Is(err, io.EOF) {
		return assetError("runtime.asset_invalid", detail, errors.New("multiple JSON values"))
	}
	return nil
}

func requireRecipePath(ctx context.Context, path, detail string) error {
	command := exec.CommandContext(ctx, "jq", "-n", "-f", path)
	command.Stdout = nil
	command.Stderr = nil
	err := command.Run()
	if err == nil {
		return nil
	}
	if ctx.Err() != nil {
		return interruptedError(ctx.Err())
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		switch exitErr.ExitCode() {
		case 1, 4, 5:
			return nil
		default:
			return assetError("runtime.asset_invalid", detail, err)
		}
	}
	var execErr *exec.Error
	if errors.As(err, &execErr) {
		return newCommandError(commandError{
			Exit: exitUnavailable, Reason: "tool.unavailable", Detail: "jq", Cause: errors.Join(errUnavailable, err),
		})
	}
	return assetError("runtime.asset_invalid", detail, err)
}

func assetError(reason, detail string, cause error) *commandError {
	if cause == nil {
		cause = errData
	}
	return newCommandError(commandError{Exit: exitData, Reason: reason, Detail: detail, Cause: cause})
}
