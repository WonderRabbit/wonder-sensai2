package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"testing"
)

func Test_loadProgress_rejects_unknown_key_from_original_candidate(t *testing.T) {
	// Given
	directory := t.TempDir()
	recipe := filepath.Join(directory, "progress.jq")
	if err := os.WriteFile(recipe, []byte(`
if .mode == "validate" and (.progress | has("unexpected") | not)
then true
else error("unexpected key")
end
`), 0600); err != nil {
		t.Fatal(err)
	}
	candidate := filepath.Join(directory, "candidate.json")
	if err := os.WriteFile(candidate, []byte(`{"unexpected":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	run := missionRun{
		ctx: context.Background(),
		assets: missionAssets{
			progressRecipe: resolvedAsset{path: recipe},
		},
	}

	// When
	_, _, err := run.loadProgress(candidate)

	// Then
	if err == nil {
		t.Fatal("candidate with an unknown key was accepted after typed re-marshalling")
	}
}

func Test_parseMissionRevision_preserves_typed_invalid_reason(t *testing.T) {
	// Given / When
	_, err := parseMissionRevision("not-a-revision")

	// Then
	var commandErr *commandError
	if !errors.As(err, &commandErr) {
		t.Fatalf("revision error type = %T, want *commandError", err)
	}
	if commandErr.Exit != exitData || commandErr.Reason != "mission.revision_invalid" || commandErr.Detail != "expected_revision" {
		t.Fatalf("revision error = exit %d reason %q detail %q", commandErr.Exit, commandErr.Reason, commandErr.Detail)
	}
}

func Test_parseMissionHash_preserves_typed_invalid_reason(t *testing.T) {
	// Given / When
	err := parseMissionHash("not-a-hash")

	// Then
	var commandErr *commandError
	if !errors.As(err, &commandErr) {
		t.Fatalf("hash error type = %T, want *commandError", err)
	}
	if commandErr.Exit != exitData || commandErr.Reason != "mission.hash_invalid" || commandErr.Detail != "expected_sha256" {
		t.Fatalf("hash error = exit %d reason %q detail %q", commandErr.Exit, commandErr.Reason, commandErr.Detail)
	}
}

func Test_missionWriteCommands_return_typed_argument_errors_before_runtime_setup(t *testing.T) {
	tests := []struct {
		name   string
		run    func() error
		reason string
		detail string
	}{
		{"checkpoint revision", func() error { return (cli{}).missionCheckpoint("id", "candidate.json", "bad", "") }, "mission.revision_invalid", "expected_revision"},
		{"checkpoint hash", func() error { return (cli{}).missionCheckpoint("id", "candidate.json", "1", "bad") }, "mission.hash_invalid", "expected_sha256"},
		{"resume revision", func() error { return (cli{}).missionResume("id", "bad", "") }, "mission.revision_invalid", "expected_revision"},
		{"resume hash", func() error { return (cli{}).missionResume("id", "1", "bad") }, "mission.hash_invalid", "expected_sha256"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// When
			err := test.run()

			// Then
			var commandErr *commandError
			if !errors.As(err, &commandErr) {
				t.Fatalf("argument error type = %T, want *commandError", err)
			}
			if commandErr.Exit != exitData || commandErr.Reason != test.reason || commandErr.Detail != test.detail {
				t.Fatalf("argument error = exit %d reason %q detail %q", commandErr.Exit, commandErr.Reason, commandErr.Detail)
			}
		})
	}
}

func Test_platformSignals_include_shutdown_signals_for_platform(t *testing.T) {
	// Given / When
	signals := platformSignals()

	// Then
	want := map[string]bool{"interrupt": true}
	if runtime.GOOS != "windows" {
		want["hangup"] = true
		want["terminated"] = true
	}
	for _, signal := range signals {
		delete(want, signal.String())
	}
	if len(want) != 0 {
		t.Fatalf("platform signal set is missing %v", want)
	}
}

func Test_executableTempPattern_preserves_unix_pattern_and_adds_windows_suffix(t *testing.T) {
	// Given / When
	unixPattern := executableTempPattern("sensai")
	windowsPattern := executableTempPattern("sensai.exe")

	// Then
	if unixPattern != ".sensai-install.*" {
		t.Fatalf("Unix executable temp pattern = %q", unixPattern)
	}
	if windowsPattern != ".sensai-install.*.exe" {
		t.Fatalf("Windows executable temp pattern = %q", windowsPattern)
	}
}

func Test_validateSourceContract_rejects_manifest_comments_and_ascii_controls_before_exact_set(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{{name: "leading comment", data: []byte("#comment\n")}}
	for value := 0; value <= 31; value++ {
		data := []byte{'a', byte(value), 'b', '\n'}
		if value == '\n' {
			data = []byte{'\n'}
		}
		tests = append(tests, struct {
			name string
			data []byte
		}{name: "control " + strconv.Itoa(value), data: data})
	}
	tests = append(tests, struct {
		name string
		data []byte
	}{name: "delete", data: []byte{'a', 0x7f, 'b', '\n'}})

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Given
			root := t.TempDir()
			if err := os.Mkdir(filepath.Join(root, "output"), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(root, "manifest.txt"), test.data, 0600); err != nil {
				t.Fatal(err)
			}
			layout := runtimeLayout{mode: runtimeSource, sourceRoot: root}

			// When
			err := layout.validateSourceContract()

			// Then
			var commandErr *commandError
			if !errors.As(err, &commandErr) {
				t.Fatalf("manifest error type = %T, want *commandError", err)
			}
			if commandErr.Exit != exitData || commandErr.Reason != "package.manifest_invalid" {
				t.Fatalf("manifest error = exit %d reason %q detail %q", commandErr.Exit, commandErr.Reason, commandErr.Detail)
			}
		})
	}
}

func Test_mergeMissionTempCleanup_preserves_primary_and_types_cleanup_failure(t *testing.T) {
	// Given
	primary := missionError(exitData, "progress.resume.corrupt", "candidate", errData)
	closeErr := errors.New("close failed")
	removeErr := errors.New("remove failed")
	cleanupErr := errors.Join(closeErr, removeErr)

	// When
	withPrimary := mergeMissionTempCleanup(primary, "checkpoint", cleanupErr)
	withoutPrimary := mergeMissionTempCleanup(nil, "checkpoint", cleanupErr)

	// Then
	var primaryCommand *commandError
	if !errors.As(withPrimary, &primaryCommand) || primaryCommand.Reason != primary.Reason {
		t.Fatalf("primary error was masked: %v", withPrimary)
	}
	if !errors.Is(withPrimary, closeErr) || !errors.Is(withPrimary, removeErr) {
		t.Fatalf("cleanup causes were discarded: %v", withPrimary)
	}
	var cleanupCommand *commandError
	if !errors.As(withoutPrimary, &cleanupCommand) || cleanupCommand.Exit != exitUnavailable ||
		cleanupCommand.Reason != "mission.temp_cleanup_failed" || cleanupCommand.Detail != "checkpoint" {
		t.Fatalf("cleanup error was not typed: %v", withoutPrimary)
	}
}

func Test_removeMissionTemp_leaves_no_sensai_residue(t *testing.T) {
	// Given
	directory := t.TempDir()
	path, err := writeSyncedTemp(directory, ".sensai-test.*", []byte("data"))
	if err != nil {
		t.Fatal(err)
	}

	// When
	err = removeMissionTemp(path)

	// Then
	if err != nil {
		t.Fatal(err)
	}
	matches, err := filepath.Glob(filepath.Join(directory, ".sensai-*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("temporary residue remains: %v", matches)
	}
}

func Test_installRollback_preserves_distinct_same_byte_replacement(t *testing.T) {
	// Given
	directory := t.TempDir()
	work := filepath.Join(directory, "work")
	if err := os.Mkdir(work, 0700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "managed")
	content := []byte("same bytes")
	if err := os.WriteFile(path, content, 0600); err != nil {
		t.Fatal(err)
	}
	published, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	transaction := installTransaction{
		work: work,
		created: []createdPackageFile{{
			path:      path,
			hash:      hashBytes(content),
			published: published,
		}},
	}
	replacement := filepath.Join(directory, "replacement")
	if err := os.WriteFile(replacement, content, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(replacement, path); err != nil {
		t.Fatal(err)
	}

	// When
	err = transaction.finish(false)

	// Then
	if err == nil {
		t.Fatal("rollback accepted a distinct same-byte file as its publication")
	}
	if _, statErr := os.Lstat(path); statErr != nil {
		t.Fatalf("distinct replacement was removed: %v", statErr)
	}
}
