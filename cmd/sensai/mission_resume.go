package main

import (
	"encoding/json"
	"errors"
)

func (c cli) missionResume(id, revisionRaw, expectedHash string) (result error) {
	expectedRevision := 0
	var err error
	if revisionRaw != "" {
		expectedRevision, err = parseMissionRevision(revisionRaw)
		if err != nil {
			return err
		}
		if err := parseMissionHash(expectedHash); err != nil {
			return err
		}
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
	lock, err := run.acquireLock(paths)
	if err != nil {
		return err
	}
	defer func() {
		if cleanupErr := lock.cleanup(); cleanupErr != nil {
			result = missionError(exitUnavailable, "mission.lock_cleanup_failed", "resume", errors.Join(result, cleanupErr))
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
	if expectedHash != "" && expectedHash != activeHash {
		return missionError(exitTemporary, "progress.resume.stale_hash", "active_progress", errTemporary)
	}
	if expectedRevision != 0 && expectedRevision != active.Revision {
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
	if active.Status == "completed" {
		return missionError(exitData, "progress.resume.terminal", "completed", errData)
	}
	observed, err := run.observe(paths, active)
	if err != nil {
		return missionMappedError(err, exitData, "progress.resume.precondition_inputs", "target")
	}
	if err := requireMissionPreconditions(active, observed); err != nil {
		return err
	}
	if err := run.validateApprovals(active, paths, observed); err != nil {
		return err
	}
	projection, err := run.validateResume(active, activeHash, observed, missionLockOwner{
		MissionID: paths.id, Owner: lock.token, BaseRevision: active.Revision,
		BaseProgressSHA256: activeHash, Exclusive: true,
	})
	if err != nil {
		return missionMappedError(err, exitTemporary, "progress.resume.invalid", "envelope")
	}
	updatedAt, err := run.utcNowAfter(active.UpdatedAt)
	if err != nil {
		return missionError(exitUnavailable, "mission.clock_unavailable", "monotonic", err)
	}
	next := active
	next.Revision++
	next.PreconditionFingerprints = missionFingerprints{
		Trace: observed.Trace, Inputs: observed.Inputs, PreviousProgress: activeHash,
		GitHead: observed.GitHead, Toolchain: observed.Toolchain,
	}
	next.UpdatedAt = updatedAt
	if err := run.validateTransition(active, next, activeHash, observed); err != nil {
		return missionMappedError(err, exitData, "progress.transition.invalid", "resume_candidate")
	}
	statusData, err := run.renderStatus(next)
	if err != nil {
		return missionMappedError(err, exitData, "progress.status_invalid", "resume_candidate")
	}
	progressData, err := marshalJSON(next)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "resume_candidate", err)
	}
	progressTemp, err := writeSyncedTemp(paths.dir, ".sensai-progress-next.*.json", progressData)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "resume_candidate", err)
	}
	defer func() {
		result = mergeMissionTempCleanup(result, "resume", removeMissionTemp(progressTemp))
	}()
	statusTemp, err := writeSyncedTemp(paths.dir, ".sensai-status.*.md", statusData)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "status_candidate", err)
	}
	defer func() {
		result = mergeMissionTempCleanup(result, "resume", removeMissionTemp(statusTemp))
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
		return missionError(exitUnavailable, "mission.lock_cleanup_failed", "resume", err)
	}
	committedHash, err := hashFile(paths.progress)
	if err != nil {
		return missionError(exitUnavailable, "mission.hash_unavailable", "committed", err)
	}
	response := struct {
		MissionID      string        `json:"mission_id"`
		Phase          string        `json:"phase"`
		Status         string        `json:"status"`
		Revision       int           `json:"revision"`
		ProgressSHA256 string        `json:"progress_sha256"`
		Next           string        `json:"next"`
		TodoSnapshot   []string      `json:"todo_snapshot"`
		Todo           []missionTodo `json:"todo"`
		ModelAdmission string        `json:"model_admission"`
	}{paths.id, next.Phase, next.Status, next.Revision, committedHash, next.Next,
		next.TodoSnapshot, projection.Todo, "UNVERIFIED"}
	output, err := marshalJSON(response)
	if err != nil {
		return missionError(exitUnavailable, "mission.write_failed", "resume_projection", err)
	}
	if _, err := c.stdout.Write(output); err != nil {
		return missionError(exitUnavailable, "runtime.output_failed", "mission_resume", err)
	}
	return nil
}

func (run *missionRun) validateResume(progress missionProgress, hash string, observed missionObserved, owner missionLockOwner) (missionResumeProjection, error) {
	envelope := struct {
		Mode                 string           `json:"mode"`
		Progress             missionProgress  `json:"progress"`
		ProgressSHA256       string           `json:"progress_sha256"`
		ActiveProgressSHA256 string           `json:"active_progress_sha256"`
		ExpectedRevision     int              `json:"expected_revision"`
		ObservedFingerprints missionObserved  `json:"observed_fingerprints"`
		Lock                 missionLockOwner `json:"lock"`
	}{"resume", progress, hash, hash, progress.Revision, observed, owner}
	input, err := marshalJSON(envelope)
	if err != nil {
		return missionResumeProjection{}, err
	}
	output, err := run.runJQ([]string{"-e", "-f", run.assets.progressRecipe.path}, input)
	if err != nil {
		return missionResumeProjection{}, err
	}
	var projection missionResumeProjection
	if err := json.Unmarshal(output, &projection); err != nil {
		return missionResumeProjection{}, errors.Join(errData, err)
	}
	return projection, nil
}
