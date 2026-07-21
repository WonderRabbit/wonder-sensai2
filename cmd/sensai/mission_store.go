package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type missionLock struct {
	run      *missionRun
	paths    missionPaths
	token    string
	acquired bool
	recorded bool
}

func (run *missionRun) acquireLock(paths missionPaths) (*missionLock, error) {
	lock := &missionLock{run: run, paths: paths, token: fmt.Sprintf("pid-%d", os.Getpid())}
	if err := os.Mkdir(paths.lock, 0700); err != nil {
		return nil, missionError(exitTemporary, "progress.resume.concurrent", "lock_exists", errTemporary)
	}
	lock.acquired = true
	return lock, nil
}

func (lock *missionLock) record(revision int, hash string) (result error) {
	if !lock.acquired {
		return missionError(exitUnavailable, "mission.lock_write_failed", "not_owned", errUnavailable)
	}
	owner := missionLockOwner{
		MissionID: lock.paths.id, Owner: lock.token, BaseRevision: revision,
		BaseProgressSHA256: hash, Exclusive: true,
	}
	data, err := marshalJSON(owner)
	if err != nil {
		return missionError(exitUnavailable, "mission.lock_write_failed", "candidate", err)
	}
	temporary, err := writeSyncedTemp(lock.paths.lock, ".sensai-owner.*", data)
	if err != nil {
		return missionError(exitUnavailable, "mission.lock_write_failed", "candidate", err)
	}
	defer func() {
		result = mergeMissionTempCleanup(result, "lock_owner", removeMissionTemp(temporary))
	}()
	if err := replaceAtomic(temporary, filepath.Join(lock.paths.lock, "owner")); err != nil {
		return missionError(exitUnavailable, "mission.lock_write_failed", "owner", err)
	}
	lock.recorded = true
	return nil
}

func (lock *missionLock) verify(revision int, hash string) bool {
	owner, fields, err := loadMissionLock(filepath.Join(lock.paths.lock, "owner"))
	return err == nil && len(fields) == 5 && owner.MissionID == lock.paths.id && owner.Owner == lock.token &&
		owner.BaseRevision == revision && owner.BaseProgressSHA256 == hash && owner.Exclusive
}

func (lock *missionLock) ownerMatches() bool {
	owner, _, err := loadMissionLock(filepath.Join(lock.paths.lock, "owner"))
	return err == nil && owner.MissionID == lock.paths.id && owner.Owner == lock.token && owner.Exclusive
}

func (lock *missionLock) release() error {
	if !lock.acquired {
		return nil
	}
	if !lock.recorded || !lock.ownerMatches() {
		return errUnavailable
	}
	if err := os.Remove(filepath.Join(lock.paths.lock, "owner")); err != nil {
		return err
	}
	if err := os.Remove(lock.paths.lock); err != nil {
		return err
	}
	lock.acquired = false
	lock.recorded = false
	return nil
}

func (lock *missionLock) cleanup() error {
	if !lock.acquired {
		return nil
	}
	if !lock.recorded {
		if err := os.Remove(lock.paths.lock); err != nil {
			return err
		}
		lock.acquired = false
		return nil
	}
	if !lock.ownerMatches() {
		return nil
	}
	if err := os.Remove(filepath.Join(lock.paths.lock, "owner")); err != nil {
		return err
	}
	if err := os.Remove(lock.paths.lock); err != nil {
		return err
	}
	lock.acquired = false
	lock.recorded = false
	return nil
}

func loadMissionLock(path string) (missionLockOwner, map[string]json.RawMessage, error) {
	data, fields, err := readJSONObject(path)
	if err != nil {
		return missionLockOwner{}, nil, err
	}
	var owner missionLockOwner
	if err := json.Unmarshal(data, &owner); err != nil {
		return missionLockOwner{}, nil, err
	}
	return owner, fields, nil
}

func (lock *missionLock) testPause() error {
	if os.Getenv("SENSAI_TEST_INTERNAL") != "1" {
		return nil
	}
	if os.Getenv("SENSAI_TEST_MISSION_INTERRUPT") == "after-lock" {
		capture := os.Getenv("SENSAI_TEST_MISSION_CAPTURE")
		if !lock.validTestPath(capture, ".sensai-test-capture.") {
			return missionError(exitData, "mission.test_hook_invalid", "capture_path", errData)
		}
		data, err := os.ReadFile(filepath.Join(lock.paths.lock, "owner"))
		if err != nil {
			return missionError(exitUnavailable, "mission.test_hook_failed", "capture", err)
		}
		if err := writeSyncedFile(capture, data, 0600); err != nil {
			return missionError(exitUnavailable, "mission.test_hook_failed", "capture", err)
		}
		return interruptedError(errors.New("mission test interrupt"))
	}
	if os.Getenv("SENSAI_TEST_MISSION_PAUSE") != "after-lock" {
		return nil
	}
	ready := os.Getenv("SENSAI_TEST_MISSION_READY")
	if !lock.validTestPath(ready, ".sensai-test-ready.") {
		return missionError(exitData, "mission.test_hook_invalid", "ready_path", errData)
	}
	if err := writeSyncedFile(ready, nil, 0600); err != nil {
		return missionError(exitUnavailable, "mission.test_hook_failed", "ready", err)
	}
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	timeout := time.NewTimer(30 * time.Second)
	defer timeout.Stop()
	for {
		if _, err := os.Lstat(ready + ".release"); err == nil {
			return nil
		}
		select {
		case <-lock.run.ctx.Done():
			return interruptedError(lock.run.ctx.Err())
		case <-timeout.C:
			return missionError(exitTemporary, "mission.test_hook_timeout", "after-lock", errTemporary)
		case <-ticker.C:
		}
	}
}

func (lock *missionLock) validTestPath(path, prefix string) bool {
	return filepath.Dir(path) == lock.run.project && strings.HasPrefix(filepath.Base(path), prefix)
}

func writeSyncedTemp(directory, pattern string, data []byte) (returnedPath string, result error) {
	file, err := os.CreateTemp(directory, pattern)
	if err != nil {
		return "", err
	}
	path := file.Name()
	complete := false
	defer func() {
		if !complete {
			cleanupErr := errors.Join(file.Close(), removeMissionTemp(path))
			result = mergeMissionTempCleanup(result, "writer", cleanupErr)
		}
	}()
	if _, err := file.Write(data); err != nil {
		return "", err
	}
	if err := file.Sync(); err != nil {
		return "", err
	}
	if err := file.Close(); err != nil {
		return "", err
	}
	complete = true
	return path, nil
}

func writeSyncedFile(path string, data []byte, mode os.FileMode) (result error) {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	complete := false
	defer func() {
		if !complete {
			cleanupErr := errors.Join(file.Close(), removeMissionTemp(path))
			result = mergeMissionTempCleanup(result, "writer", cleanupErr)
		}
	}()
	if _, err := file.Write(data); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	complete = true
	return nil
}

func removeMissionTemp(path string) error {
	err := os.Remove(path)
	if isPathMissing(err) {
		return nil
	}
	return err
}

func mergeMissionTempCleanup(primary error, detail string, cleanupErr error) error {
	if cleanupErr == nil {
		return primary
	}
	typedCleanup := missionError(exitUnavailable, "mission.temp_cleanup_failed", detail, cleanupErr)
	if primary == nil {
		return typedCleanup
	}
	return errors.Join(primary, typedCleanup)
}

func missionContextError(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return interruptedError(err)
	}
	return nil
}
