package main

import (
	"encoding/json"
	"io"
	"os"
)

type modelAliases struct {
	Lead  string `json:"lead"`
	Small string `json:"small"`
}

type toolchainConfig struct {
	OpenCodeVersion string       `json:"opencode_version"`
	ModelAliases    modelAliases `json:"model_aliases"`
	ModelAdmission  string       `json:"model_admission"`
}

type providerOptions struct {
	BaseURL string `json:"baseURL"`
}

type providerModel struct {
	Name string `json:"name"`
}

type providerConfig struct {
	NPM     string                   `json:"npm"`
	Options providerOptions          `json:"options"`
	Models  map[string]providerModel `json:"models"`
}

type openCodeConfig struct {
	DefaultAgent string                    `json:"default_agent"`
	Model        string                    `json:"model"`
	SmallModel   string                    `json:"small_model"`
	Provider     map[string]providerConfig `json:"provider"`
}

func (c cli) doctorModels() error {
	if err := c.runtime.validateSourceContract(); err != nil {
		return err
	}
	assets, err := resolveGlobalAssets()
	if err != nil {
		return err
	}
	var lock toolchainConfig
	if err := decodeConfig(assets.toolchainLock, "toolchain.lock.json", &lock); err != nil {
		return err
	}
	if lock.OpenCodeVersion != "1.18.3" || lock.ModelAliases.Lead != "zai/glm-5.2" ||
		lock.ModelAliases.Small != "sensai-ollama/qwen3.5:9b" || lock.ModelAdmission != "UNVERIFIED" {
		return newCommandError(commandError{
			Exit: exitData, Reason: "model.alias_mismatch", Detail: "toolchain_lock", Cause: errData,
		})
	}
	var config openCodeConfig
	if err := decodeConfig(assets.opencode, "opencode.json", &config); err != nil {
		return err
	}
	provider, present := config.Provider["sensai-ollama"]
	_, modelPresent := provider.Models["qwen3.5:9b"]
	if config.DefaultAgent != "sensai-analysis-lead" || config.Model != "zai/glm-5.2" ||
		config.SmallModel != "sensai-ollama/qwen3.5:9b" || !present || !modelPresent {
		return newCommandError(commandError{
			Exit: exitData, Reason: "model.alias_mismatch", Detail: "opencode_config", Cause: errData,
		})
	}
	if provider.NPM != "@ai-sdk/openai-compatible" || provider.Options.BaseURL != "http://localhost:11434/v1" {
		return newCommandError(commandError{
			Exit: exitUnavailable, Reason: "model.transport_unavailable", Detail: "configured_transport", Cause: errUnavailable,
		})
	}
	lines := "모델 discovery=READY reason=model.config_ready\n" +
		"모델 alias=zai/glm-5.2 admission=UNVERIFIED reason=MODEL_ADMISSION_UNVERIFIED\n" +
		"모델 alias=sensai-ollama/qwen3.5:9b admission=UNVERIFIED reason=MODEL_ADMISSION_UNVERIFIED\n"
	if _, err := io.WriteString(c.stdout, lines); err != nil {
		return newCommandError(commandError{
			Exit: exitUnavailable, Reason: "runtime.output_failed", Detail: "doctor_models", Cause: err,
		})
	}
	return nil
}

func decodeConfig[T toolchainConfig | openCodeConfig](path, detail string, destination *T) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return assetError("runtime.asset_invalid", detail, err)
	}
	if err := json.Unmarshal(data, destination); err != nil {
		return assetError("runtime.asset_invalid", detail, err)
	}
	return nil
}
