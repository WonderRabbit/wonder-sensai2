package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type packageClassification struct {
	absent      []string
	unchanged   int
	cliIsAbsent bool
}

type installTarget struct {
	home       string
	configRoot string
	cliParent  string
	cli        string
}

func (c cli) install() (result error) {
	if c.runtime.mode != runtimeSource {
		return packageCommandError(exitData, "runtime.asset_invalid", "source_layout_required", errData)
	}
	target, err := resolveInstallTarget()
	if err != nil {
		return err
	}
	work, err := os.MkdirTemp(os.TempDir(), "sensai-install.*")
	if err != nil {
		return packageCommandError(exitCantCreate, "package.stage_create_failed", "work_collision", err)
	}
	transaction := installTransaction{target: target, work: work}
	finalized := false
	defer func() {
		if finalized {
			return
		}
		cleanupErr := transaction.finish(result == nil)
		if cleanupErr != nil {
			result = rollbackFailure(cleanupErr)
		}
	}()
	source, err := preparePackageSource(c.runtime, work)
	if err != nil {
		return err
	}
	transaction.source = source
	cliSnapshot := filepath.Join(work, platformExecutableName())
	cliHash, err := copyRegularLeaf(c.runtime.executable, cliSnapshot)
	if err != nil {
		return packageCommandError(exitData, "package.source_cli_invalid", "executable", err)
	}
	if err := preparePlatformExecutable(cliSnapshot); err != nil {
		return packageCommandError(exitCantCreate, "package.mode_failed", "cli", err)
	}
	transaction.cliSnapshot = cliSnapshot
	transaction.cliHash = cliHash
	if _, err := transaction.classify(); err != nil {
		return err
	}
	if err := transaction.acquireLocks(); err != nil {
		return err
	}
	classification, err := transaction.classify()
	if err != nil {
		return err
	}
	if err := source.verifySourceUnchanged(); err != nil {
		return err
	}
	currentCLIHash, err := hashRegularFile(c.runtime.executable)
	if err != nil || currentCLIHash != cliHash {
		return packageCommandError(exitData, "package.source_hash_drift", "cli", err)
	}
	for _, entry := range classification.absent {
		if err := transaction.publishConfig(entry); err != nil {
			return err
		}
		if err := c.ctx.Err(); err != nil {
			return interruptedError(err)
		}
	}
	cliResult := "unchanged"
	if classification.cliIsAbsent {
		if err := transaction.publishFile(cliSnapshot, target.cli, cliHash, true); err != nil {
			return err
		}
		cliResult = "created"
	}
	configHash, err := transaction.verifyInstalled()
	if err != nil {
		return err
	}
	pathContains := pathContainsDirectory(os.Getenv("PATH"), target.cliParent)
	transaction.committed = true
	cleanupErr := transaction.finish(true)
	finalized = true
	if cleanupErr != nil {
		return rollbackFailure(cleanupErr)
	}
	_, err = fmt.Fprintf(c.stdout,
		"패키지 mode=install status=READY config_target=%s cli_target=%s leaf_count=%d manifest_sha256=%s config_sha256=%s cli_sha256=%s config_created=%d config_unchanged=%d cli_result=%s path_contains_local_bin=%t\n",
		target.configRoot, target.cli, len(source.manifest), source.manifestHash, configHash, cliHash,
		len(classification.absent), classification.unchanged, cliResult, pathContains)
	if err == nil && !pathContains {
		_, err = fmt.Fprintln(c.stdout, `안내 export PATH="$HOME/.local/bin:$PATH"`)
	}
	if err != nil {
		return packageCommandError(exitUnavailable, "runtime.output_failed", "install", err)
	}
	return nil
}

func resolveInstallTarget() (installTarget, error) {
	home := platformHome()
	if home == "" {
		return installTarget{}, packageCommandError(exitData, "package.home_invalid", "missing", errData)
	}
	if !normalizedAbsolutePath(home) {
		return installTarget{}, packageCommandError(exitData, "package.home_invalid", "not_normalized", errData)
	}
	if err := inspectPathComponents(home); err != nil {
		return installTarget{}, packageCommandError(exitCantCreate, "package.home_invalid", "symlink", err)
	}
	info, err := os.Lstat(home)
	if err != nil || !info.IsDir() {
		return installTarget{}, packageCommandError(exitCantCreate, "package.home_invalid", "not_directory", err)
	}
	physical, err := filepath.EvalSymlinks(home)
	if err != nil || physical != home {
		return installTarget{}, packageCommandError(exitData, "package.home_invalid", "not_physical", err)
	}
	target := installTarget{
		home: home, configRoot: filepath.Join(home, ".config", "opencode"),
		cliParent: filepath.Join(home, ".local", "bin"),
	}
	target.cli = filepath.Join(target.cliParent, platformExecutableName())
	if err := requireInstallDirectory(target.configRoot, "package.config_root_invalid", "missing_or_not_directory"); err != nil {
		return installTarget{}, err
	}
	for _, path := range []string{filepath.Join(home, ".local"), target.cliParent} {
		info, err := os.Lstat(path)
		if isPathMissing(err) {
			continue
		}
		if err != nil || !info.IsDir() {
			return installTarget{}, packageCommandError(exitCantCreate, "package.cli_parent_invalid", "not_directory", err)
		}
		if err := inspectPathComponents(path); err != nil {
			return installTarget{}, packageCommandError(exitCantCreate, "package.cli_parent_invalid", "symlink", err)
		}
	}
	return target, nil
}

func requireInstallDirectory(path, reason, detail string) error {
	if err := inspectPathComponents(path); err != nil {
		return packageCommandError(exitCantCreate, reason, "symlink", err)
	}
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() {
		return packageCommandError(exitCantCreate, reason, detail, err)
	}
	physical, err := filepath.EvalSymlinks(path)
	if err != nil || physical != path {
		return packageCommandError(exitData, reason, "not_physical", err)
	}
	return nil
}

func pathContainsDirectory(pathValue, directory string) bool {
	for _, entry := range filepath.SplitList(pathValue) {
		if entry == directory {
			return true
		}
	}
	return false
}

func managedConflict(detail string, cause error) *commandError {
	return packageCommandError(exitCantCreate, "package.managed_conflict", strings.TrimSpace(detail), cause)
}
