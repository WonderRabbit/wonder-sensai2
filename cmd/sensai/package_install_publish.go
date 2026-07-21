package main

import (
	"errors"
	"io"
	"os"
	"path/filepath"
)

func (transaction *installTransaction) publishConfig(entry string) error {
	parent := transaction.target.configRoot
	components := splitAssetEntry(entry)
	for _, component := range components[:len(components)-1] {
		parent = filepath.Join(parent, component)
		if err := transaction.ensureDirectory(parent); err != nil {
			return err
		}
	}
	source := filepath.Join(transaction.source.tree, filepath.FromSlash(entry))
	target := filepath.Join(transaction.target.configRoot, filepath.FromSlash(entry))
	hash, err := hashRegularFile(source)
	if err != nil {
		return packageCommandError(exitUnavailable, "package.hash_failed", entry, err)
	}
	return transaction.publishFile(source, target, hash, false)
}

func (transaction *installTransaction) publishFile(source, target, expectedHash string, executable bool) error {
	if err := inspectPathComponents(target); err != nil {
		return managedConflict(target, err)
	}
	if _, err := os.Lstat(target); err == nil {
		return managedConflict(target, errCantCreate)
	} else if !isPathMissing(err) {
		return managedConflict(target, err)
	}
	tempPattern := ".sensai-install.*"
	if executable {
		tempPattern = platformExecutableTempPattern()
	}
	tempFile, err := os.CreateTemp(filepath.Dir(target), tempPattern)
	if err != nil {
		return packageCommandError(exitCantCreate, "package.publish_failed", "temp_collision", err)
	}
	temp := tempFile.Name()
	transaction.temps = append(transaction.temps, temp)
	input, err := os.Open(source)
	if err != nil {
		return packageCommandError(
			exitCantCreate, "package.publish_failed", "copy", errors.Join(err, tempFile.Close()),
		)
	}
	_, copyErr := io.Copy(tempFile, input)
	inputCloseErr := input.Close()
	closeErr := tempFile.Close()
	if copyErr != nil || inputCloseErr != nil || closeErr != nil {
		return packageCommandError(exitCantCreate, "package.publish_failed", "copy", errors.Join(copyErr, inputCloseErr, closeErr))
	}
	if executable {
		if err := preparePlatformExecutable(temp); err != nil {
			return packageCommandError(exitCantCreate, "package.publish_failed", "mode", err)
		}
	}
	hash, err := hashRegularFile(temp)
	if err != nil || hash != expectedHash {
		return packageCommandError(exitData, "package.stage_hash_mismatch", target, err)
	}
	if err := inspectPathComponents(target); err != nil {
		return managedConflict(target, err)
	}
	if _, err := os.Lstat(target); err == nil {
		return managedConflict(target, errCantCreate)
	} else if !isPathMissing(err) {
		return managedConflict(target, err)
	}
	if err := publishNoReplace(temp, target); err != nil {
		if owned, claimErr := publishedFromTemp(temp, target, expectedHash); owned {
			if recordErr := transaction.recordCreatedFile(target, expectedHash); recordErr != nil {
				return rollbackFailure(errors.Join(err, recordErr))
			}
			return packageCommandError(exitCantCreate, "package.publish_failed", "publish", err)
		} else if claimErr != nil {
			return rollbackFailure(claimErr)
		}
		if _, statErr := os.Lstat(target); statErr == nil {
			return managedConflict(target, err)
		}
		return packageCommandError(exitCantCreate, "package.publish_failed", "publish", err)
	}
	transaction.temps[len(transaction.temps)-1] = ""
	if err := transaction.recordCreatedFile(target, expectedHash); err != nil {
		return rollbackFailure(err)
	}
	return nil
}

func executableTempPattern(executableName string) string {
	return ".sensai-install.*" + filepath.Ext(executableName)
}

func (transaction *installTransaction) recordCreatedFile(target, expectedHash string) error {
	if err := inspectPathComponents(target); err != nil {
		return managedConflict(target, err)
	}
	info, err := os.Lstat(target)
	if err != nil || !info.Mode().IsRegular() {
		return packageCommandError(exitData, "package.installed_state_invalid", target, errors.Join(errData, err))
	}
	hash, err := hashRegularFile(target)
	if err != nil || hash != expectedHash {
		return packageCommandError(exitData, "package.installed_hash_mismatch", target, errors.Join(errData, err))
	}
	transaction.created = append(transaction.created, createdPackageFile{path: target, hash: expectedHash, published: info})
	return nil
}

func publishedFromTemp(temp, target, expectedHash string) (bool, error) {
	if err := inspectPathComponents(temp); err != nil {
		return false, err
	}
	if err := inspectPathComponents(target); err != nil {
		return false, err
	}
	tempInfo, tempErr := os.Lstat(temp)
	targetInfo, targetErr := os.Lstat(target)
	if tempErr != nil || targetErr != nil {
		return false, nil
	}
	if !tempInfo.Mode().IsRegular() || !targetInfo.Mode().IsRegular() || !os.SameFile(tempInfo, targetInfo) {
		return false, nil
	}
	hash, err := hashRegularFile(target)
	if err != nil || hash != expectedHash {
		return false, errors.Join(errData, err)
	}
	return true, nil
}

func (transaction *installTransaction) verifyInstalled() (string, error) {
	hashes := make([]string, 0, len(transaction.source.manifest))
	for _, entry := range transaction.source.manifest {
		target := filepath.Join(transaction.target.configRoot, filepath.FromSlash(entry))
		if err := inspectPathComponents(target); err != nil {
			return "", packageCommandError(exitData, "package.installed_state_invalid", entry, err)
		}
		hash, err := hashRegularFile(target)
		if err != nil {
			return "", packageCommandError(exitData, "package.installed_state_invalid", entry, err)
		}
		hashes = append(hashes, hashLine(hash, entry))
	}
	if !equalStrings(transaction.source.leafHashes, hashes) {
		return "", packageCommandError(exitData, "package.installed_hash_mismatch", "config", errData)
	}
	configHash := hashBytes([]byte(joinHashLines(hashes)))
	if err := inspectPathComponents(transaction.target.cli); err != nil {
		return "", packageCommandError(exitData, "package.installed_state_invalid", "cli", err)
	}
	cliHash, err := hashRegularFile(transaction.target.cli)
	if err != nil || cliHash != transaction.cliHash {
		return "", packageCommandError(exitData, "package.installed_hash_mismatch", "cli", err)
	}
	info, err := os.Lstat(transaction.target.cli)
	if err != nil || !packageExecutableModeOK(info) {
		return "", packageCommandError(exitData, "package.installed_state_invalid", "cli", err)
	}
	equal, err := filesEqual(transaction.cliSnapshot, transaction.target.cli)
	if err != nil || !equal {
		return "", packageCommandError(exitData, "package.installed_state_invalid", "cli", err)
	}
	return configHash, nil
}
