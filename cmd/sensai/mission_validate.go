package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"reflect"
)

var traceArrayKeys = []string{
	"evidence", "conventions", "requirements", "frontends", "backends", "business_entities",
	"business_rules", "business_flows", "business_events", "business_states", "business_invariants",
	"extension_requirements", "designs", "bindings", "unknowns", "unsupported", "provenance",
}

func (run *missionRun) validateTrace(path string) error {
	data, fields, err := readJSONObject(path)
	if err != nil {
		return err
	}
	allowed := map[string]bool{"schema_version": true, "mission_id": true, "glossary_ref": true, "joins": true}
	for _, key := range traceArrayKeys {
		allowed[key] = true
		if _, present := fields[key]; !present {
			return errData
		}
	}
	for key := range fields {
		if !allowed[key] {
			return errData
		}
	}
	var schemaVersion, missionID string
	if json.Unmarshal(fields["schema_version"], &schemaVersion) != nil || schemaVersion != "2.0" ||
		json.Unmarshal(fields["mission_id"], &missionID) != nil || !missionIDPattern.MatchString(missionID) {
		return errData
	}
	for _, key := range append(traceArrayKeys, "joins") {
		if raw, present := fields[key]; present {
			var array []json.RawMessage
			if json.Unmarshal(raw, &array) != nil || array == nil {
				return errData
			}
		}
	}
	_, err = run.runJQ([]string{"-e", "-f", run.assets.traceRecipe.path}, data)
	return err
}

func (run *missionRun) loadProgress(path string) (missionProgress, []byte, error) {
	data, _, err := readJSONObject(path)
	if err != nil {
		return missionProgress{}, nil, err
	}
	var progress missionProgress
	if err := json.Unmarshal(data, &progress); err != nil {
		return missionProgress{}, nil, err
	}
	envelope := struct {
		Mode     string          `json:"mode"`
		Progress json.RawMessage `json:"progress"`
	}{Mode: "validate", Progress: data}
	input, err := marshalJSON(envelope)
	if err != nil {
		return missionProgress{}, nil, err
	}
	if _, err := run.runJQ([]string{"-e", "-f", run.assets.progressRecipe.path}, input); err != nil {
		return missionProgress{}, nil, err
	}
	return progress, data, nil
}

func (run *missionRun) renderStatus(progress missionProgress) ([]byte, error) {
	envelope := struct {
		Mode     string          `json:"mode"`
		Progress missionProgress `json:"progress"`
	}{Mode: "status", Progress: progress}
	input, err := marshalJSON(envelope)
	if err != nil {
		return nil, err
	}
	return run.runJQ([]string{"-r", "-e", "-f", run.assets.progressRecipe.path}, input)
}

func (run *missionRun) observe(paths missionPaths, progress missionProgress) (missionObserved, error) {
	if len(progress.Provenance) == 0 {
		return missionObserved{}, errData
	}
	inputs, err := run.hashTarget(progress.Provenance[0].Path)
	if err != nil {
		return missionObserved{}, err
	}
	trace, err := hashFile(paths.trace)
	if err != nil {
		return missionObserved{}, err
	}
	toolchain, err := hashFile(run.assets.global.toolchainLock)
	if err != nil {
		return missionObserved{}, err
	}
	gitHead, err := run.gitHead()
	if err != nil {
		return missionObserved{}, err
	}
	return missionObserved{Trace: trace, Inputs: inputs, GitHead: gitHead, Toolchain: toolchain}, nil
}

func requireMissionPreconditions(progress missionProgress, observed missionObserved) error {
	expected := progress.PreconditionFingerprints
	if expected.Trace != observed.Trace {
		return missionError(exitTemporary, "progress.resume.precondition_trace", "mismatch", errTemporary)
	}
	if expected.Inputs != observed.Inputs {
		return missionError(exitTemporary, "progress.resume.precondition_inputs", "mismatch", errTemporary)
	}
	if expected.GitHead != "" && expected.GitHead != observed.GitHead {
		return missionError(exitTemporary, "progress.resume.precondition_git_head", "mismatch", errTemporary)
	}
	if expected.Toolchain != "" && expected.Toolchain != observed.Toolchain {
		return missionError(exitTemporary, "progress.resume.precondition_toolchain", "mismatch", errTemporary)
	}
	return nil
}

func (run *missionRun) validateApprovals(progress missionProgress, paths missionPaths, observed missionObserved) error {
	for _, approval := range progress.Approvals {
		path, err := run.resolveProjectPath(approval.ReceiptPath)
		if err != nil {
			return missionError(exitData, "progress.approval_receipt", "unsafe_or_missing", err)
		}
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() || info.Mode()&fs.ModeSymlink != 0 {
			return missionError(exitData, "progress.approval_receipt", "not_regular", errors.Join(errData, err))
		}
		hash, err := hashFile(path)
		if err != nil {
			return missionError(exitUnavailable, "mission.hash_unavailable", "approval", err)
		}
		if hash != approval.ReceiptSHA256 {
			return missionError(exitData, "progress.approval_receipt", "hash_mismatch", errData)
		}
		_, fields, err := readJSONObject(path)
		if err != nil || len(fields) != 9 {
			return missionError(exitData, "progress.approval_receipt", "content_mismatch", errors.Join(errData, err))
		}
		var receipt struct {
			MissionID, Gate, Verdict, Reason, ActorRole, Source, RecordedAt, TraceSHA256, InputsSHA256 string
		}
		bindings := map[string]*string{
			"mission_id": &receipt.MissionID, "gate": &receipt.Gate, "verdict": &receipt.Verdict,
			"reason": &receipt.Reason, "actor_role": &receipt.ActorRole, "source": &receipt.Source,
			"recorded_at": &receipt.RecordedAt, "trace_sha256": &receipt.TraceSHA256,
			"inputs_sha256": &receipt.InputsSHA256,
		}
		for key, destination := range bindings {
			raw, present := fields[key]
			if !present || json.Unmarshal(raw, destination) != nil {
				return missionError(exitData, "progress.approval_receipt", "content_mismatch", errData)
			}
		}
		actual := []string{receipt.MissionID, receipt.Gate, receipt.Verdict, receipt.Reason, receipt.ActorRole,
			receipt.Source, receipt.RecordedAt, receipt.TraceSHA256, receipt.InputsSHA256}
		expected := []string{paths.id, approval.Gate, approval.Verdict, approval.Reason, approval.ActorRole,
			approval.Source, approval.RecordedAt, observed.Trace, observed.Inputs}
		if !reflect.DeepEqual(actual, expected) {
			return missionError(exitData, "progress.approval_receipt", "content_mismatch", errData)
		}
	}
	return nil
}

func (run *missionRun) runJQ(args []string, input []byte) ([]byte, error) {
	command := exec.CommandContext(run.ctx, "jq", args...)
	command.Stdin = bytes.NewReader(input)
	command.Stderr = nil
	output, err := command.Output()
	if run.ctx.Err() != nil {
		return nil, interruptedError(run.ctx.Err())
	}
	if err != nil {
		var execErr *exec.Error
		if errors.As(err, &execErr) {
			return nil, toolUnavailable("jq", err)
		}
		return nil, err
	}
	return output, nil
}

func readJSONObject(path string) ([]byte, map[string]json.RawMessage, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&fs.ModeSymlink != 0 {
		return nil, nil, errors.Join(errData, err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	var fields map[string]json.RawMessage
	if err := decoder.Decode(&fields); err != nil || fields == nil {
		return nil, nil, errors.Join(errData, err)
	}
	if err := decoder.Decode(new(json.RawMessage)); !errors.Is(err, io.EOF) {
		return nil, nil, errData
	}
	return data, fields, nil
}

func marshalJSON[T any](value T) ([]byte, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}
