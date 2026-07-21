package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

type packageSource struct {
	root         string
	tree         string
	manifest     []string
	manifestHash string
	payloadHash  string
	leafHashes   []string
}

func preparePackageSource(layout runtimeLayout, workRoot string) (packageSource, error) {
	if layout.mode != runtimeSource {
		return packageSource{}, packageCommandError(exitData, "runtime.asset_invalid", "source_layout_required", errData)
	}
	if err := layout.validateSourceContract(); err != nil {
		return packageSource{}, err
	}
	manifestPath := filepath.Join(layout.sourceRoot, "manifest.txt")
	manifest, err := readManifest(manifestPath)
	if err != nil || len(manifest) != 36 {
		return packageSource{}, packageCommandError(exitData, "package.manifest_invalid", "count_or_content", err)
	}
	manifestHash, err := hashRegularFile(manifestPath)
	if err != nil {
		return packageSource{}, packageCommandError(exitUnavailable, "package.hash_failed", "manifest", err)
	}
	tree := filepath.Join(workRoot, "tree")
	if err := os.Mkdir(tree, 0700); err != nil {
		return packageSource{}, packageCommandError(exitCantCreate, "package.stage_create_failed", "tree", err)
	}
	sourceRoot := filepath.Join(layout.sourceRoot, "output")
	hashes := make([]string, 0, len(manifest))
	for _, entry := range manifest {
		sourcePath := filepath.Join(sourceRoot, filepath.FromSlash(entry))
		destination := filepath.Join(tree, filepath.FromSlash(entry))
		hash, copyErr := copyRegularLeaf(sourcePath, destination)
		if copyErr != nil {
			return packageSource{}, packageCommandError(exitData, "package.source_leaf_invalid", entry, copyErr)
		}
		hashes = append(hashes, hashLine(hash, entry))
	}
	payloadHash := hashBytes([]byte(joinHashLines(hashes)))
	source := packageSource{
		root: layout.sourceRoot, tree: tree, manifest: manifest,
		manifestHash: manifestHash, payloadHash: payloadHash, leafHashes: hashes,
	}
	if err := source.verifySourceUnchanged(); err != nil {
		return packageSource{}, err
	}
	return source, nil
}

func (source packageSource) verifySourceUnchanged() error {
	current := make([]string, 0, len(source.manifest))
	for _, entry := range source.manifest {
		path := filepath.Join(source.root, "output", filepath.FromSlash(entry))
		hash, err := hashRegularFile(path)
		if err != nil {
			return packageCommandError(exitData, "package.source_leaf_invalid", entry, err)
		}
		current = append(current, hashLine(hash, entry))
	}
	if !equalStrings(source.leafHashes, current) {
		return packageCommandError(exitData, "package.source_hash_drift", "payload", errData)
	}
	return nil
}

func copyRegularLeaf(source, destination string) (string, error) {
	if err := inspectPathComponents(source); err != nil {
		return "", err
	}
	before, err := os.Lstat(source)
	if err != nil || !before.Mode().IsRegular() {
		return "", errors.Join(errData, err)
	}
	input, err := os.Open(source)
	if err != nil {
		return "", err
	}
	defer input.Close()
	opened, err := input.Stat()
	if err != nil || !os.SameFile(before, opened) {
		return "", errors.Join(errData, err)
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		return "", err
	}
	output, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return "", err
	}
	hasher := sha256.New()
	_, copyErr := io.Copy(io.MultiWriter(output, hasher), input)
	closeErr := output.Close()
	if copyErr != nil || closeErr != nil {
		return "", errors.Join(copyErr, closeErr)
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func hashRegularFile(path string) (string, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() {
		return "", errors.Join(errData, err)
	}
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	opened, err := file.Stat()
	if err != nil || !os.SameFile(info, opened) {
		return "", errors.Join(errData, err)
	}
	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func filesEqual(left, right string) (bool, error) {
	leftBytes, err := os.ReadFile(left)
	if err != nil {
		return false, err
	}
	rightBytes, err := os.ReadFile(right)
	if err != nil {
		return false, err
	}
	return bytes.Equal(leftBytes, rightBytes), nil
}

func hashLine(hash, entry string) string { return fmt.Sprintf("%s  %s\n", hash, entry) }

func joinHashLines(lines []string) string {
	var buffer bytes.Buffer
	for _, line := range lines {
		buffer.WriteString(line)
	}
	return buffer.String()
}

func hashBytes(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func packageCommandError(exit int, reason, detail string, cause error) *commandError {
	if cause == nil {
		cause = errData
	}
	return newCommandError(commandError{Exit: exit, Reason: reason, Detail: detail, Cause: cause})
}
