package main

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

type createdPackageFile struct {
	path      string
	hash      string
	published fs.FileInfo
}

type ownedPackageDirectory struct {
	path    string
	created fs.FileInfo
}

type installTransaction struct {
	target      installTarget
	work        string
	source      packageSource
	cliSnapshot string
	cliHash     string
	locks       []ownedPackageDirectory
	ownedDirs   []ownedPackageDirectory
	temps       []string
	created     []createdPackageFile
	committed   bool
}

func (transaction *installTransaction) classify() (packageClassification, error) {
	classification := packageClassification{absent: make([]string, 0, 36)}
	for _, entry := range transaction.source.manifest {
		target := filepath.Join(transaction.target.configRoot, filepath.FromSlash(entry))
		state, err := managedFileState(transaction.target.configRoot, target, transaction.source.tree, entry)
		if err != nil {
			return packageClassification{}, managedConflict(entry, err)
		}
		switch state {
		case managedAbsent:
			classification.absent = append(classification.absent, entry)
		case managedEqual:
			classification.unchanged++
		default:
			return packageClassification{}, managedConflict(entry, errData)
		}
	}
	if err := inspectPathComponents(transaction.target.cli); err != nil {
		return packageClassification{}, managedConflict("cli", err)
	}
	info, err := os.Lstat(transaction.target.cli)
	if isPathMissing(err) {
		classification.cliIsAbsent = true
		return classification, nil
	}
	if err != nil || !info.Mode().IsRegular() || !packageExecutableModeOK(info) {
		return packageClassification{}, managedConflict("cli", err)
	}
	equal, err := filesEqual(transaction.cliSnapshot, transaction.target.cli)
	if err != nil || !equal {
		return packageClassification{}, managedConflict("cli", err)
	}
	return classification, nil
}

type managedState uint8

const (
	managedAbsent managedState = iota
	managedEqual
	managedConflictState
)

func managedFileState(root, target, snapshotRoot, entry string) (managedState, error) {
	if err := inspectPathComponents(target); err != nil {
		return managedConflictState, err
	}
	current := root
	for _, component := range splitAssetEntry(entry) {
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if isPathMissing(err) {
			return managedAbsent, nil
		}
		if err != nil {
			return managedConflictState, err
		}
		if current != target {
			if !info.IsDir() {
				return managedConflictState, errData
			}
			continue
		}
		if !info.Mode().IsRegular() {
			return managedConflictState, errData
		}
		equal, err := filesEqual(filepath.Join(snapshotRoot, filepath.FromSlash(entry)), target)
		if err != nil || !equal {
			return managedConflictState, err
		}
		return managedEqual, nil
	}
	return managedConflictState, errData
}

func splitAssetEntry(entry string) []string {
	return strings.Split(entry, "/")
}

func (transaction *installTransaction) acquireLocks() error {
	configLock := filepath.Join(transaction.target.configRoot, ".sensai-install-lock")
	if err := os.Mkdir(configLock, 0700); err != nil {
		return packageCommandError(exitTemporary, "package.locked", "config_root", err)
	}
	ownedConfigLock, err := inspectOwnedDirectory(configLock)
	if err != nil {
		return rollbackFailure(err)
	}
	transaction.locks = append(transaction.locks, ownedConfigLock)
	if err := transaction.ensureDirectory(filepath.Join(transaction.target.home, ".local")); err != nil {
		return err
	}
	if err := transaction.ensureDirectory(transaction.target.cliParent); err != nil {
		return err
	}
	cliLock := filepath.Join(transaction.target.cliParent, ".sensai-install-lock")
	if err := os.Mkdir(cliLock, 0700); err != nil {
		return packageCommandError(exitTemporary, "package.locked", "cli_parent", err)
	}
	ownedCLILock, err := inspectOwnedDirectory(cliLock)
	if err != nil {
		return rollbackFailure(err)
	}
	transaction.locks = append(transaction.locks, ownedCLILock)
	return nil
}

func (transaction *installTransaction) ensureDirectory(path string) error {
	info, err := os.Lstat(path)
	if err == nil {
		if !info.IsDir() || inspectPathComponents(path) != nil {
			return managedConflict(path, errData)
		}
		return nil
	}
	if !isPathMissing(err) {
		return managedConflict(path, err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		return managedConflict(path, err)
	}
	owned, err := inspectOwnedDirectory(path)
	if err != nil {
		return rollbackFailure(err)
	}
	transaction.ownedDirs = append(transaction.ownedDirs, owned)
	return nil
}

func (transaction *installTransaction) finish(success bool) error {
	failed := false
	if !success && !transaction.committed {
		for index := len(transaction.created) - 1; index >= 0; index-- {
			created := transaction.created[index]
			if inspectPathComponents(created.path) != nil {
				failed = true
				continue
			}
			current, statErr := os.Lstat(created.path)
			hash, err := hashRegularFile(created.path)
			if statErr != nil || created.published == nil || !os.SameFile(created.published, current) ||
				err != nil || hash != created.hash || os.Remove(created.path) != nil {
				failed = true
			}
		}
	}
	for _, temp := range transaction.temps {
		if temp == "" {
			continue
		}
		if err := removeOwnedRegular(temp); err != nil {
			failed = true
		}
	}
	for index := len(transaction.locks) - 1; index >= 0; index-- {
		if err := removeOwnedDirectory(transaction.locks[index]); err != nil {
			failed = true
		}
	}
	if !success && !transaction.committed {
		for index := len(transaction.ownedDirs) - 1; index >= 0; index-- {
			if err := removeOwnedDirectory(transaction.ownedDirs[index]); err != nil {
				failed = true
			}
		}
	}
	if err := os.RemoveAll(transaction.work); err != nil {
		failed = true
	}
	if failed {
		return errors.New("owned transaction state could not be cleaned")
	}
	return nil
}

func inspectOwnedDirectory(path string) (ownedPackageDirectory, error) {
	if err := inspectPathComponents(path); err != nil {
		return ownedPackageDirectory{}, err
	}
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() {
		return ownedPackageDirectory{}, errors.Join(errData, err)
	}
	return ownedPackageDirectory{path: path, created: info}, nil
}

func removeOwnedDirectory(owned ownedPackageDirectory) error {
	if err := inspectPathComponents(owned.path); err != nil {
		return err
	}
	info, err := os.Lstat(owned.path)
	if err != nil || owned.created == nil || !info.IsDir() || !os.SameFile(owned.created, info) {
		return errors.Join(errData, err)
	}
	return os.Remove(owned.path)
}

func removeOwnedRegular(path string) error {
	if err := inspectPathComponents(path); err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if isPathMissing(err) {
		return nil
	}
	if err != nil || !info.Mode().IsRegular() {
		return errors.Join(errData, err)
	}
	return os.Remove(path)
}
