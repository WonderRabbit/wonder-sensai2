package main

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"strconv"
)

func (c cli) missionCheckpoint(id, candidateRelative, revisionRaw, expectedHash string) (result error) {
	expectedRevision, err := parseMissionRevision(revisionRaw)
	if err != nil {
		return err
	}
	if err := parseMissionHash(expectedHash); err != nil {
		return err
	}
	run, err := c.prepareMission()
	if err != nil {
		return err
	}
	paths, err := run.paths(id)
	if err != nil {
		return err
	}
	if err := requireMissionDirectory(paths); err != nil {
		return err
	}
	candidatePath, err := run.resolveProjectPath(candidateRelative)
	if err != nil {
		return missionError(exitData, "mission.candidate_invalid", "unsafe_path", err)
	}
	candidateInfo, err := os.Lstat(candidatePath)
	if err != nil || !candidateInfo.Mode().IsRegular() {
		return missionError(exitData, "mission.candidate_invalid", "not_file", errors.Join(errData, err))
	}
	lock, err := run.acquireLock(paths)
	if err != nil {
		return err
	}
	defer func() {
		if cleanupErr := lock.cleanup(); cleanupErr != nil {
			result = missionError(exitUnavailable, "mission.lock_cleanup_failed", "checkpoint", errors.Join(result, cleanupErr))
		}
	}()
	if err := run.validateTrace(paths.trace); err != nil {
		return missionMappedError(err, exitData, "progress.resume.corrupt", "trace")
	}
	active, _, err := run.loadProgress(paths.progress)
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.corrupt", "progress")
	}
	activeHash, err := hashFile(paths.progress)
	if err != nil {
		return missionError(exitUnavailable, "mission.hash_unavailable", "progress", err)
	}
	if activeHash != expectedHash {
		return missionError(exitTemporary, "progress.resume.stale_hash", "active_progress", errTemporary)
	}
	if active.Revision != expectedRevision {
		return missionError(exitTemporary, "progress.resume.stale_revision", "active_progress", errTemporary)
	}
	if err := lock.record(active.Revision, activeHash); err != nil {
		return err
	}
	if !lock.verify(active.Revision, activeHash) {
		return missionError(exitTemporary, "progress.resume.double_resume", "lock_mismatch", errTemporary)
	}
	if err := lock.testPause(); err != nil {
		return err
	}
	candidate, candidateData, err := run.loadProgress(candidatePath)
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.corrupt", "candidate")
	}
	observed, err := run.observe(paths, active)
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.precondition_inputs", "target")
	}
	if err := requireMissionPreconditions(active, observed); err != nil {
		return err
	}
	if err := run.validateApprovals(candidate, paths, observed); err != nil {
		return err
	}
	if err := run.validateTransition(active, candidate, activeHash, observed); err != nil {
		return missionMappedError(err, exitData, "progress.transition.invalid", "candidate")
	}
	statusData, err := run.renderStatus(candidate)
	if err != nil {
		return missionMappedError(err, exitData, "progress.status_invalid", "candidate")
	}
	progressTemp, err := writeSyncedTemp(paths.dir, ".sensai-progress.*.json", candidateData)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "checkpoint_copy", err)
	}
	defer func() {
		result = mergeMissionTempCleanup(result, "checkpoint", removeMissionTemp(progressTemp))
	}()
	statusTemp, err := writeSyncedTemp(paths.dir, ".sensai-status.*.md", statusData)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "status_candidate", err)
	}
	defer func() {
		result = mergeMissionTempCleanup(result, "checkpoint", removeMissionTemp(statusTemp))
	}()
	currentHash, err := hashFile(paths.progress)
	if err != nil {
		return missionError(exitUnavailable, "mission.hash_unavailable", "pre_rename", err)
	}
	if currentHash != activeHash {
		return missionError(exitTemporary, "progress.resume.stale_hash", "pre_rename", errTemporary)
	}
	if !lock.verify(active.Revision, activeHash) {
		return missionError(exitTemporary, "progress.resume.double_resume", "lock_mismatch", errTemporary)
	}
	if err := missionContextError(run.ctx); err != nil {
		return err
	}
	if err := replaceAtomic(progressTemp, paths.progress); err != nil {
		return missionError(exitUnavailable, "mission.atomic_rename_failed", "progress", err)
	}
	if err := replaceAtomic(statusTemp, paths.status); err != nil {
		return missionError(exitUnavailable, "mission.atomic_rename_failed", "status", err)
	}
	if err := lock.release(); err != nil {
		return missionError(exitUnavailable, "mission.lock_cleanup_failed", "checkpoint", err)
	}
	committedHash, err := hashFile(paths.progress)
	if err != nil {
		return missionError(exitUnavailable, "mission.hash_unavailable", "committed", err)
	}
	_, err = fmt.Fprintf(c.stdout, "미션 mission_id=%s status=CHECKPOINTED revision=%d progress_sha256=%s\n",
		paths.id, candidate.Revision, committedHash)
	if err != nil {
		return missionError(exitUnavailable, "runtime.output_failed", "mission_checkpoint", err)
	}
	return nil
}

func (run *missionRun) validateTransition(previous, current missionProgress, previousHash string, observed missionObserved) error {
	envelope := struct {
		Mode                 string          `json:"mode"`
		Previous             missionProgress `json:"previous"`
		Current              missionProgress `json:"current"`
		PreviousSHA256       string          `json:"previous_sha256"`
		ActiveProgressSHA256 string          `json:"active_progress_sha256"`
		ObservedFingerprints missionObserved `json:"observed_fingerprints"`
	}{"transition", previous, current, previousHash, previousHash, observed}
	input, err := marshalJSON(envelope)
	if err != nil {
		return err
	}
	_, err = run.runJQ([]string{"-e", "-f", run.assets.progressRecipe.path}, input)
	return err
}

func requireMissionDirectory(paths missionPaths) error {
	info, err := os.Lstat(paths.dir)
	if err != nil || !info.IsDir() || info.Mode()&fs.ModeSymlink != 0 || inspectPathComponents(paths.dir) != nil {
		return missionError(exitData, "mission.path_invalid", "missing_or_symlink", errors.Join(errData, err))
	}
	return nil
}

func parseMissionRevision(value string) (int, error) {
	revision, err := strconv.Atoi(value)
	if err != nil || revision < 1 {
		return 0, missionError(exitData, "mission.revision_invalid", "expected_revision", errors.Join(errData, err))
	}
	return revision, nil
}

func parseMissionHash(value string) error {
	if len(value) != 64 || !isLowerHex(value) {
		return missionError(exitData, "mission.hash_invalid", "expected_sha256", errData)
	}
	return nil
}

func (c cli) missionStatus(id string) error {
	run, err := c.prepareMission()
	if err != nil {
		return err
	}
	paths, err := run.paths(id)
	if err != nil {
		return err
	}
	if err := requireMissionDirectory(paths); err != nil {
		return err
	}
	if err := run.validateTrace(paths.trace); err != nil {
		return missionMappedError(err, exitData, "progress.resume.corrupt", "trace")
	}
	progress, _, err := run.loadProgress(paths.progress)
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.corrupt", "progress")
	}
	observed, err := run.observe(paths, progress)
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.precondition_inputs", "target")
	}
	if err := requireMissionPreconditions(progress, observed); err != nil {
		return err
	}
	if err := run.validateApprovals(progress, paths, observed); err != nil {
		return err
	}
	status, err := run.renderStatus(progress)
	if err != nil {
		return missionMappedError(err, exitData, "progress.status_invalid", "current")
	}
	view := "stale"
	if saved, err := os.ReadFile(paths.status); err == nil {
		if info, statErr := os.Lstat(paths.status); statErr == nil && info.Mode().IsRegular() && info.Mode()&fs.ModeSymlink == 0 && bytes.Equal(saved, status) {
			view = "current"
		}
	}
	if _, err := c.stdout.Write(status); err != nil {
		return missionError(exitUnavailable, "runtime.output_failed", "mission_status", err)
	}
	if _, err := fmt.Fprintf(c.stdout, "- status_view: `%s`\n", view); err != nil {
		return missionError(exitUnavailable, "runtime.output_failed", "mission_status", err)
	}
	return nil
}
