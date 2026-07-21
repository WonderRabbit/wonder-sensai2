package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
)

func resolveProjectRoot() (string, error) {
	request := os.Getenv("SENSAI_PROJECT_ROOT")
	if request == "" {
		cwd, err := os.Getwd()
		if err != nil {
			return "", projectRootError("unresolved", err)
		}
		request = cwd
	}
	if !normalizedAbsolutePath(request) || request == filepath.VolumeName(request)+string(filepath.Separator) {
		return "", projectRootError("unsafe_or_relative", errData)
	}
	if err := inspectPathComponents(request); err != nil {
		return "", projectRootError("link", err)
	}
	info, err := os.Lstat(request)
	if err != nil || !info.IsDir() {
		if err == nil {
			err = errData
		}
		return "", projectRootError("non_directory", err)
	}
	physical, err := filepath.EvalSymlinks(request)
	if err != nil || physical != request {
		if err == nil {
			err = errData
		}
		return "", projectRootError("not_physical", err)
	}
	return request, nil
}

func projectRootError(detail string, cause error) *commandError {
	return newCommandError(commandError{
		Exit: exitData, Reason: "mission.project_root_invalid", Detail: detail, Cause: cause,
	})
}

func resolveMissionAssets(ctx context.Context) (missionAssets, error) {
	global, err := resolveGlobalAssets()
	if err != nil {
		return missionAssets{}, err
	}
	project, err := resolveProjectRoot()
	if err != nil {
		return missionAssets{}, err
	}
	projectAssets := filepath.Join(project, ".sensai")
	traceSchema, err := resolveOverlayAsset(projectAssets, global.root, "schemas/trace.schema.json")
	if err != nil {
		return missionAssets{}, err
	}
	if err := requireJSONPath(traceSchema.path, "schemas/trace.schema.json"); err != nil {
		return missionAssets{}, err
	}
	progressSchema, err := resolveOverlayAsset(projectAssets, global.root, "schemas/progress.schema.json")
	if err != nil {
		return missionAssets{}, err
	}
	if err := requireJSONPath(progressSchema.path, "schemas/progress.schema.json"); err != nil {
		return missionAssets{}, err
	}
	traceRecipe, err := resolveOverlayAsset(projectAssets, global.root, "recipes/trace.jq")
	if err != nil {
		return missionAssets{}, err
	}
	if err := requireRecipePath(ctx, traceRecipe.path, "recipes/trace.jq"); err != nil {
		return missionAssets{}, err
	}
	progressRecipe, err := resolveOverlayAsset(projectAssets, global.root, "recipes/progress.jq")
	if err != nil {
		return missionAssets{}, err
	}
	if err := requireRecipePath(ctx, progressRecipe.path, "recipes/progress.jq"); err != nil {
		return missionAssets{}, err
	}
	return missionAssets{
		global:         global,
		traceSchema:    traceSchema,
		progressSchema: progressSchema,
		traceRecipe:    traceRecipe,
		progressRecipe: progressRecipe,
	}, nil
}

func resolveOverlayAsset(projectRoot, globalRoot, relative string) (resolvedAsset, error) {
	path, present, err := resolveRegularAsset(projectRoot, relative, true)
	if err != nil {
		return resolvedAsset{}, err
	}
	if present {
		return resolvedAsset{path: path, provenance: provenanceProject}, nil
	}
	path, present, err = resolveRegularAsset(globalRoot, relative, false)
	if err != nil {
		return resolvedAsset{}, err
	}
	if !present {
		return resolvedAsset{}, assetError("runtime.asset_missing", relative, errors.New("global asset missing"))
	}
	return resolvedAsset{path: path, provenance: provenanceGlobal}, nil
}
