package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

func (c cli) missionInit(id, target, goal string) (result error) {
	run, err := c.prepareMission()
	if err != nil {
		return err
	}
	paths, err := run.paths(id)
	if err != nil {
		return err
	}
	if !safeMissionRelative(target) {
		return missionError(exitData, "mission.target_invalid", "unsafe_path", errData)
	}
	if goal == "" {
		return missionError(exitData, "mission.goal_invalid", "empty", errData)
	}
	inputsHash, err := run.hashTarget(target)
	if err != nil {
		return missionError(exitData, "mission.target_invalid", "unresolved_or_symlink", err)
	}
	toolchainHash, err := hashFile(run.assets.global.toolchainLock)
	if err != nil {
		return missionError(exitUnavailable, "mission.toolchain_unavailable", "hash_failed", err)
	}
	gitHead, err := run.gitHead()
	if err != nil {
		return missionError(exitUnavailable, "mission.git_state_unavailable", "read_failed", err)
	}
	timestamp, err := run.utcNowAfter("")
	if err != nil {
		return missionError(exitUnavailable, "mission.clock_unavailable", "utc", err)
	}

	parent := filepath.Join(run.project, "docs", "analysis", "missions")
	if err := inspectPathComponents(filepath.Join(run.project, "docs")); err != nil {
		return missionError(exitData, "mission.path_symlink", "docs", err)
	}
	if err := os.MkdirAll(parent, 0755); err != nil {
		return missionError(exitUnavailable, "mission.root_unavailable", "mkdir", err)
	}
	if err := inspectPathComponents(parent); err != nil {
		return missionError(exitData, "mission.path_symlink", "mission_parent", err)
	}
	if _, err := os.Lstat(paths.dir); err == nil || !errors.Is(err, fs.ErrNotExist) {
		return missionError(exitTemporary, "mission.already_exists", "existing", errTemporary)
	}

	initLock := filepath.Join(parent, ".sensai-init-"+paths.id+".lock")
	if err := os.Mkdir(initLock, 0700); err != nil {
		return missionError(exitTemporary, "progress.resume.concurrent", "init_lock", errTemporary)
	}
	lockOwned := true
	defer func() {
		if lockOwned {
			if cleanupErr := os.Remove(initLock); cleanupErr != nil {
				result = missionError(exitUnavailable, "mission.lock_cleanup_failed", "init", errors.Join(result, cleanupErr))
			}
		}
	}()
	stage, err := os.MkdirTemp(parent, ".sensai-init-"+paths.id+".")
	if err != nil {
		return missionError(exitTemporary, "mission.init_conflict", "stage", err)
	}
	stageOwned := true
	defer func() {
		if stageOwned {
			if cleanupErr := os.RemoveAll(stage); cleanupErr != nil {
				result = missionError(exitUnavailable, "mission.write_failed", "init_cleanup", errors.Join(result, cleanupErr))
			}
		}
	}()

	empty := []json.RawMessage{}
	trace := missionTrace{
		SchemaVersion: "2.0", MissionID: paths.id,
		Evidence: empty, Conventions: empty, Requirements: empty, Frontends: empty, Backends: empty,
		Joins: empty, BusinessEntities: empty, BusinessRules: empty, BusinessFlows: empty,
		BusinessEvents: empty, BusinessStates: empty, BusinessInvariants: empty,
		ExtensionRequirements: empty, Designs: empty, Bindings: empty, Unknowns: empty,
		Unsupported: empty, Provenance: []missionProvenance{{Path: target, Line: 1, PathLine: target + ":1"}},
	}
	traceData, err := marshalJSON(trace)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "trace_candidate", err)
	}
	if err := writeSyncedFile(filepath.Join(stage, "trace.json"), traceData, 0644); err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "trace_candidate", err)
	}
	if err := run.validateTrace(filepath.Join(stage, "trace.json")); err != nil {
		return missionMappedError(err, exitData, "mission.trace_invalid", "initialized_trace")
	}
	traceHash, err := hashFile(filepath.Join(stage, "trace.json"))
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "trace_hash", err)
	}
	progress := missionProgress{
		SchemaVersion: "1.0", MissionID: paths.id, MissionRoot: paths.relative + "/",
		Phase: "F0", Status: "planned", Revision: 1,
		TodoSnapshot: []string{"F0 미션 계획과 사람 승인 대기"},
		PreconditionFingerprints: missionFingerprints{
			Trace: traceHash, Inputs: inputsHash, GitHead: gitHead, Toolchain: toolchainHash,
		},
		Next:    "F0 계획을 검토하고 사람 승인 영수증을 기록한다",
		Blocked: []string{}, Unknowns: []string{}, Approvals: []missionApproval{},
		Writer: "sensai-analysis-lead", UpdatedAt: timestamp,
		Provenance: []missionProvenance{{Path: target, Line: 1, PathLine: target + ":1"}},
	}
	progressData, err := marshalJSON(progress)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "progress_candidate", err)
	}
	if err := writeSyncedFile(filepath.Join(stage, "progress.json"), progressData, 0644); err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "progress_candidate", err)
	}
	validated, _, err := run.loadProgress(filepath.Join(stage, "progress.json"))
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.corrupt", "initialized_progress")
	}
	statusData, err := run.renderStatus(validated)
	if err != nil {
		return missionMappedError(err, exitData, "progress.status_invalid", "initialized_progress")
	}
	if err := writeSyncedFile(filepath.Join(stage, "status.md"), statusData, 0644); err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "status_candidate", err)
	}
	if err := missionContextError(run.ctx); err != nil {
		return err
	}
	if _, err := os.Lstat(paths.dir); err == nil || !errors.Is(err, fs.ErrNotExist) {
		return missionError(exitTemporary, "mission.already_exists", "raced", errTemporary)
	}
	if err := inspectPathComponents(paths.dir); err != nil {
		return missionError(exitData, "mission.path_symlink", "mission_destination", err)
	}
	if err := publishDirectoryNoReplace(stage, paths.dir); err != nil {
		return missionError(exitTemporary, "mission.atomic_rename_failed", "init", err)
	}
	stageOwned = false
	if err := os.Remove(initLock); err != nil {
		return missionError(exitUnavailable, "mission.lock_cleanup_failed", "init", err)
	}
	lockOwned = false
	progressHash, err := hashFile(paths.progress)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "progress_hash", err)
	}
	_, err = fmt.Fprintf(c.stdout, "미션 mission_id=%s status=INITIALIZED revision=1 progress_sha256=%s\n", paths.id, progressHash)
	if err != nil {
		return missionError(exitUnavailable, "runtime.output_failed", "mission_init", err)
	}
	return nil
}

func missionMappedError(err error, exit int, reason, detail string) error {
	var commandErr *commandError
	if errors.As(err, &commandErr) && (commandErr.Exit == exitInterrupted || commandErr.Exit == exitUnavailable) {
		return err
	}
	return missionError(exit, reason, detail, err)
}
