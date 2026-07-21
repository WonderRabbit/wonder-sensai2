package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

var missionIDPattern = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)

type missionRun struct {
	ctx     context.Context
	project string
	assets  missionAssets
}

func (c cli) prepareMission() (*missionRun, error) {
	if err := c.runtime.validateSourceContract(); err != nil {
		return nil, err
	}
	if _, err := exec.LookPath("jq"); err != nil {
		return nil, toolUnavailable("jq", err)
	}
	if _, err := exec.LookPath("git"); err != nil {
		return nil, toolUnavailable("git", err)
	}
	project, err := resolveProjectRoot()
	if err != nil {
		return nil, err
	}
	assets, err := resolveMissionAssets(c.ctx)
	if err != nil {
		return nil, err
	}
	if _, err := fmt.Fprintf(c.stderr,
		"런타임 trace_schema=%s progress_schema=%s trace_recipe=%s progress_recipe=%s\n",
		assets.traceSchema.provenance, assets.progressSchema.provenance,
		assets.traceRecipe.provenance, assets.progressRecipe.provenance); err != nil {
		return nil, missionError(exitUnavailable, "runtime.output_failed", "mission_assets", err)
	}
	return &missionRun{ctx: c.ctx, project: project, assets: assets}, nil
}

func (run *missionRun) paths(id string) (missionPaths, error) {
	if !missionIDPattern.MatchString(id) {
		return missionPaths{}, missionError(exitData, "mission.id_invalid", "invalid_slug", errData)
	}
	relative := "docs/analysis/missions/" + id
	dir := filepath.Join(run.project, filepath.FromSlash(relative))
	return missionPaths{
		id: id, relative: relative, dir: dir,
		trace: filepath.Join(dir, "trace.json"), progress: filepath.Join(dir, "progress.json"),
		status: filepath.Join(dir, "status.md"), lock: filepath.Join(dir, ".sensai-lock"),
	}, nil
}

func safeMissionRelative(relative string) bool {
	if relative == "" || relative == "." || filepath.IsAbs(relative) || strings.ContainsAny(relative, "\\\n\t") {
		return false
	}
	for _, component := range strings.Split(relative, "/") {
		if component == "" || component == "." || component == ".." {
			return false
		}
	}
	return true
}

func (run *missionRun) resolveProjectPath(relative string) (string, error) {
	if !safeMissionRelative(relative) {
		return "", errData
	}
	path := filepath.Join(run.project, filepath.FromSlash(relative))
	if err := inspectPathComponents(path); err != nil {
		return "", err
	}
	if _, err := os.Lstat(path); err != nil {
		return "", err
	}
	physicalParent, err := filepath.EvalSymlinks(filepath.Dir(path))
	if err != nil {
		return "", err
	}
	resolved := filepath.Join(physicalParent, filepath.Base(path))
	rel, err := filepath.Rel(run.project, resolved)
	if err != nil || rel == "." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", errData
	}
	info, err := os.Lstat(resolved)
	if err != nil || info.Mode()&fs.ModeSymlink != 0 {
		return "", errors.Join(errData, err)
	}
	return resolved, nil
}

func (run *missionRun) hashTarget(relative string) (string, error) {
	target, err := run.resolveProjectPath(relative)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(target)
	if err != nil {
		return "", err
	}
	if info.Mode().IsRegular() {
		return hashFile(target)
	}
	if !info.IsDir() {
		return "", errData
	}
	files := make([]string, 0)
	err = filepath.WalkDir(target, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&fs.ModeSymlink != 0 {
			return errData
		}
		if entry.IsDir() && path != target && run.excludedHashDirectory(path) {
			return filepath.SkipDir
		}
		if entry.Type().IsRegular() {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	sort.Strings(files)
	hash := sha256.New()
	writer := bufio.NewWriter(hash)
	for _, path := range files {
		relative, err := filepath.Rel(run.project, path)
		if err != nil || strings.IndexFunc(relative, func(r rune) bool { return r < 0x20 || r == 0x7f }) >= 0 {
			return "", errData
		}
		fileHash, err := hashFile(path)
		if err != nil {
			return "", err
		}
		if _, err := fmt.Fprintf(writer, "%s  %s\n", fileHash, filepath.ToSlash(relative)); err != nil {
			return "", err
		}
	}
	if err := writer.Flush(); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func (run *missionRun) excludedHashDirectory(path string) bool {
	for _, relative := range []string{".git", ".omo", "docs/analysis/missions"} {
		if path == filepath.Join(run.project, filepath.FromSlash(relative)) {
			return true
		}
	}
	return false
}

func hashFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func (run *missionRun) gitHead() (string, error) {
	command := exec.CommandContext(run.ctx, "git", "-C", run.project, "rev-parse", "--verify", "HEAD")
	output, err := command.Output()
	if run.ctx.Err() != nil {
		return "", interruptedError(run.ctx.Err())
	}
	if err != nil {
		return "UNBORN", nil
	}
	head := strings.TrimSpace(string(output))
	if len(head) != 40 || !isLowerHex(head) {
		return "", errData
	}
	return head, nil
}

func (run *missionRun) utcNowAfter(previous string) (string, error) {
	for attempt := 0; attempt < 4; attempt++ {
		now := time.Now().UTC().Truncate(time.Second).Format(time.RFC3339)
		if previous == "" || now > previous {
			return now, nil
		}
		select {
		case <-run.ctx.Done():
			return "", interruptedError(run.ctx.Err())
		case <-time.After(time.Second):
		}
	}
	return "", errUnavailable
}

func missionError(exit int, reason, detail string, cause error) *commandError {
	return newCommandError(commandError{Exit: exit, Reason: reason, Detail: detail, Cause: cause})
}

func toolUnavailable(tool string, cause error) *commandError {
	return missionError(exitUnavailable, "tool.unavailable", tool, errors.Join(errUnavailable, cause))
}

func isLowerHex(value string) bool {
	_, err := hex.DecodeString(value)
	return err == nil && value == strings.ToLower(value)
}
