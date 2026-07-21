package main

import "encoding/json"

type missionPaths struct {
	id       string
	relative string
	dir      string
	trace    string
	progress string
	status   string
	lock     string
}

type missionProvenance struct {
	Path     string `json:"path"`
	Line     int    `json:"line"`
	PathLine string `json:"path_line"`
}

type missionFingerprints struct {
	Trace            string `json:"trace"`
	Inputs           string `json:"inputs"`
	PreviousProgress string `json:"previous_progress,omitempty"`
	GitHead          string `json:"git_head,omitempty"`
	Toolchain        string `json:"toolchain,omitempty"`
}

type missionApproval struct {
	Gate          string `json:"gate"`
	Verdict       string `json:"verdict"`
	Reason        string `json:"reason"`
	ActorRole     string `json:"actor_role"`
	Source        string `json:"source"`
	ReceiptPath   string `json:"receipt_path"`
	ReceiptSHA256 string `json:"receipt_sha256"`
	RecordedAt    string `json:"recorded_at"`
}

type missionProgress struct {
	SchemaVersion            string              `json:"schema_version"`
	MissionID                string              `json:"mission_id"`
	MissionRoot              string              `json:"mission_root"`
	Phase                    string              `json:"phase"`
	Status                   string              `json:"status"`
	Revision                 int                 `json:"revision"`
	TodoSnapshot             []string            `json:"todo_snapshot"`
	PreconditionFingerprints missionFingerprints `json:"precondition_fingerprints"`
	Next                     string              `json:"next"`
	Blocked                  []string            `json:"blocked"`
	Unknowns                 []string            `json:"unknowns"`
	Approvals                []missionApproval   `json:"approvals"`
	Writer                   string              `json:"writer"`
	UpdatedAt                string              `json:"updated_at"`
	Provenance               []missionProvenance `json:"provenance"`
}

type missionTrace struct {
	SchemaVersion         string              `json:"schema_version"`
	MissionID             string              `json:"mission_id"`
	Evidence              []json.RawMessage   `json:"evidence"`
	Conventions           []json.RawMessage   `json:"conventions"`
	Requirements          []json.RawMessage   `json:"requirements"`
	Frontends             []json.RawMessage   `json:"frontends"`
	Backends              []json.RawMessage   `json:"backends"`
	Joins                 []json.RawMessage   `json:"joins"`
	BusinessEntities      []json.RawMessage   `json:"business_entities"`
	BusinessRules         []json.RawMessage   `json:"business_rules"`
	BusinessFlows         []json.RawMessage   `json:"business_flows"`
	BusinessEvents        []json.RawMessage   `json:"business_events"`
	BusinessStates        []json.RawMessage   `json:"business_states"`
	BusinessInvariants    []json.RawMessage   `json:"business_invariants"`
	ExtensionRequirements []json.RawMessage   `json:"extension_requirements"`
	Designs               []json.RawMessage   `json:"designs"`
	Bindings              []json.RawMessage   `json:"bindings"`
	Unknowns              []json.RawMessage   `json:"unknowns"`
	Unsupported           []json.RawMessage   `json:"unsupported"`
	Provenance            []missionProvenance `json:"provenance"`
}

type missionObserved struct {
	Trace     string `json:"trace"`
	Inputs    string `json:"inputs"`
	GitHead   string `json:"git_head"`
	Toolchain string `json:"toolchain"`
}

type missionLockOwner struct {
	MissionID          string `json:"mission_id"`
	Owner              string `json:"owner"`
	BaseRevision       int    `json:"base_revision"`
	BaseProgressSHA256 string `json:"base_progress_sha256"`
	Exclusive          bool   `json:"exclusive"`
}

type missionResumeProjection struct {
	Todo []missionTodo `json:"todo"`
}

type missionTodo struct {
	Content  string `json:"content"`
	Status   string `json:"status"`
	Priority string `json:"priority"`
}
