package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func (c cli) stage(target string) (result error) {
	if c.runtime.mode != runtimeSource {
		return packageCommandError(exitData, "runtime.asset_invalid", "source_layout_required", errData)
	}
	parent, base, err := validateStageTarget(target)
	if err != nil {
		return err
	}
	lock := filepath.Join(parent, ".sensai-package-lock."+base)
	if err := os.Mkdir(lock, 0700); err != nil {
		if _, statErr := os.Lstat(lock); statErr == nil {
			return packageCommandError(exitTemporary, "package.locked", "lock_exists", err)
		}
		return packageCommandError(exitCantCreate, "package.lock_create_failed", lock, err)
	}
	work, err := os.MkdirTemp(parent, ".sensai-package.*.stage")
	if err != nil {
		cleanupErr := os.Remove(lock)
		if cleanupErr != nil {
			return rollbackFailure(cleanupErr)
		}
		return packageCommandError(exitCantCreate, "package.stage_create_failed", "work_collision", err)
	}
	cleanupPending := true
	defer func() {
		if !cleanupPending {
			return
		}
		cleanupErr := cleanupStage(work, lock)
		if cleanupErr != nil {
			result = rollbackFailure(cleanupErr)
		}
	}()
	source, err := preparePackageSource(c.runtime, work)
	if err != nil {
		return err
	}
	if err := c.ctx.Err(); err != nil {
		return interruptedError(err)
	}
	if _, err := os.Lstat(target); err == nil {
		return packageCommandError(exitCantCreate, "package.target_exists", target, errCantCreate)
	} else if !isPathMissing(err) {
		return packageCommandError(exitCantCreate, "package.target_exists", target, err)
	}
	if err := publishDirectoryNoReplace(source.tree, target); err != nil {
		if _, statErr := os.Lstat(target); statErr == nil {
			return packageCommandError(exitCantCreate, "package.target_exists", target, err)
		}
		return packageCommandError(exitCantCreate, "package.atomic_move_failed", target, err)
	}
	if err := cleanupStage(work, lock); err != nil {
		cleanupPending = false
		return rollbackFailure(err)
	}
	cleanupPending = false
	_, err = fmt.Fprintf(c.stdout,
		"패키지 mode=stage status=READY files=%d manifest_sha256=%s payload_sha256=%s stage_sha256=%s target=%s\n",
		len(source.manifest), source.manifestHash, source.payloadHash, source.payloadHash, target)
	if err != nil {
		return packageCommandError(exitUnavailable, "runtime.output_failed", "stage", err)
	}
	return nil
}

func validateStageTarget(target string) (string, string, error) {
	if !filepath.IsAbs(target) {
		return "", "", packageCommandError(exitData, "package.target_not_absolute", "relative_path", errData)
	}
	if !normalizedAbsolutePath(target) || target == string(filepath.Separator) {
		return "", "", packageCommandError(exitData, "package.target_not_normalized", target, errData)
	}
	if _, err := os.Lstat(target); err == nil {
		return "", "", packageCommandError(exitCantCreate, "package.target_exists", target, errCantCreate)
	} else if !isPathMissing(err) {
		return "", "", packageCommandError(exitCantCreate, "package.target_exists", target, err)
	}
	parent := filepath.Dir(target)
	base := filepath.Base(target)
	if base == "." || base == string(filepath.Separator) {
		return "", "", packageCommandError(exitData, "package.target_invalid", "basename", errData)
	}
	if err := inspectPathComponents(parent); err != nil {
		return "", "", packageCommandError(exitCantCreate, "package.parent_invalid", "symlink_or_traversal", err)
	}
	info, err := os.Lstat(parent)
	if err != nil || !info.IsDir() {
		return "", "", packageCommandError(exitCantCreate, "package.parent_invalid", "missing_or_symlink", err)
	}
	physical, err := filepath.EvalSymlinks(parent)
	if err != nil || platformCanonicalPath(parent) != physical {
		return "", "", packageCommandError(exitCantCreate, "package.parent_invalid", "unresolved", err)
	}
	if filepath.Join(physical, base) != platformCanonicalPath(target) {
		return "", "", packageCommandError(exitData, "package.target_not_normalized", target, errData)
	}
	return physical, base, nil
}

func cleanupStage(work, lock string) error {
	workErr := os.RemoveAll(work)
	lockErr := os.Remove(lock)
	if workErr != nil {
		return workErr
	}
	return lockErr
}

func rollbackFailure(cause error) *commandError {
	return packageCommandError(exitTemporary, "package.rollback_failed", "owned_state_mismatch", cause)
}
