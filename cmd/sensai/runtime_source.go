package main

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func (layout runtimeLayout) validateSourceContract() error {
	if layout.mode != runtimeSource {
		return nil
	}
	manifestPath := filepath.Join(layout.sourceRoot, "manifest.txt")
	payloadRoot := filepath.Join(layout.sourceRoot, "output")
	if err := inspectPathComponents(manifestPath); err != nil {
		return runtimeExecutableError("source_manifest_invalid", err)
	}
	manifestInfo, err := os.Lstat(manifestPath)
	if err != nil || !manifestInfo.Mode().IsRegular() {
		return runtimeExecutableError("source_manifest_invalid", err)
	}
	if err := inspectPathComponents(payloadRoot); err != nil {
		return runtimeExecutableError("source_payload_symlink", err)
	}
	payloadInfo, err := os.Lstat(payloadRoot)
	if err != nil || !payloadInfo.IsDir() {
		return runtimeExecutableError("source_payload_invalid", err)
	}
	manifest, err := readManifest(manifestPath)
	if err != nil {
		return sourceContractError("package.manifest_invalid", "manifest.txt", err)
	}
	payload, err := listPayloadLeaves(payloadRoot)
	if err != nil {
		return sourceContractError("package.source_leaf_invalid", "output", err)
	}
	if len(manifest) != 36 || len(payload) != len(manifest) {
		return sourceContractError("package.source_exact_set_mismatch", "config_payload", errData)
	}
	for index := range manifest {
		if manifest[index] != payload[index] {
			return sourceContractError("package.source_exact_set_mismatch", "config_payload", errData)
		}
	}
	return nil
}

func sourceContractError(reason, detail string, cause error) *commandError {
	return newCommandError(commandError{Exit: exitData, Reason: reason, Detail: detail, Cause: cause})
}

func readManifest(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	entries := make([]string, 0, 36)
	lines := strings.Split(string(data), "\n")
	if len(data) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	previous := ""
	for _, entry := range lines {
		if err := safeAssetRelativePath(entry); err != nil {
			return nil, err
		}
		if previous != "" && entry <= previous {
			return nil, errors.New("manifest must be sorted and unique")
		}
		entries = append(entries, entry)
		previous = entry
	}
	return entries, nil
}

func listPayloadLeaves(root string) ([]string, error) {
	leaves := make([]string, 0, 36)
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == root {
			return nil
		}
		if entry.Type()&fs.ModeSymlink != 0 {
			return errors.New("payload symlink rejected")
		}
		if entry.IsDir() {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return errors.New("payload leaf is not regular")
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if strings.HasPrefix(relative, "../") {
			return errors.New("payload escaped root")
		}
		leaves = append(leaves, relative)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(leaves)
	return leaves, nil
}
