# 치명적 간극

## 1. 제품 가치가 기술 범위보다 늦게 검증된다

PRD는 2/9/15 topology, F0-F5, 설치·재개·Windows까지 넓지만 실제 사용자가 이 분석을 반복 사용할지 검증하는 gate가 없다. [00-overview.md:268-287](../plan/prd/00-overview.md#L268-L287)의 MVP는 작은 fixture와 render를 성공으로 삼는다. 이는 기술 smoke이지 구매·채택·업무 개선 증거가 아니다.

해결: 실제 3개 repository와 승인된 과거 변경을 사용한 concierge pilot을 첫 gate로 둔다. pilot 전 전체 catalog 구현은 NO-GO다.

## 2. MVP와 F0-F5 계약이 충돌한다

- MVP는 F2·F4·F5를 슬라이스 이후로 미룬다([00-overview.md:272-285](../plan/prd/00-overview.md#L272-L285)). 그러나 F3 W0는 F1+F2가 모두 있어야 한다([03-asis-deliverables.md:80-104](../plan/prd/03-asis-deliverables.md#L80-L104)). MVP의 UI 1개는 canonical F3가 아니라 `M0_UI_PROOF`로 이름을 분리해야 한다.
- 03은 04와 병렬일 수 있다고 하여 F3 human approval을 우회한다([03-asis-deliverables.md:40-43](../plan/prd/03-asis-deliverables.md#L40-L43)). source-owned runtime은 F3 승인 후 F4다([runtime-contract.md:38-46](../docs/harness/runtime-contract.md#L38-L46)).
- O6은 F0/F3/F5 hard gate를 정의하지만 F0 approval receipt의 stale 조건과 F5 final receipt의 typed precondition이 PRD schema에 없다([O6:73-84](../plan/prd/O6-workflow-orchestration.md#L73-L84)).
- F1/F2 병렬 lane은 가능하지만 canonical merge는 lead 한 명이 직렬로 해야 한다. todo나 permission은 compare-and-swap을 제공하지 않는다.

정합한 순서는 `M0_UI_PROOF` → F0 draft+human receipt → F1/F2 read-only lanes → lead serial merge → F3 4종+human receipt → F4 → F5 5종+human receipt다.

## 3. 원장 schema가 산출물과 변경 의미를 충분히 표현하지 못한다

[00-overview.md:130-148](../plan/prd/00-overview.md#L130-L148)은 `MSG-`, `DATA-`, `STORY-`, `TEST-` ID를 나열하지만 top-level ledger 배열은 없다. `designs[]`의 `follows_*`는 “기존 규칙을 따른다”만 표현하며 정상적인 규칙 변경, 영향, 대체를 표현하지 못한다. [04-change-design.md:107-124](../plan/prd/04-change-design.md#L107-L124)의 `gate: violation`만으로는 승인된 변경과 오류를 구별하기 어렵다.

필수 보강:

- typed binding: `implements`, `modifies`, `affects`, `preserves`, `contradicts`, `supersedes`.
- 승인된 규칙 변경: `supersedes` + fingerprint-bound `approved_exception` receipt.
- 산출 요소를 원장에 저장할지, projection-local ID로 둘지 하나로 동결.
- migration은 원문 보존, before/after hash, loss report, validator receipt를 남김.

## 4. provenance가 semantic truth를 검증하지 않는다

`path:line`이 존재하고 ID가 연결돼도 주장이 그 span에서 따라오지 않을 수 있다. 현재 설계는 self-consistent fiction을 잡지 못한다. W3C PROV도 provenance와 truth를 동일시하지 않는다([PROV-DM](https://www.w3.org/TR/prov-dm/), [PROV-CONSTRAINTS](https://www.w3.org/TR/prov-constraints/)). ALCE는 citation correctness와 completeness를 분리하고, FActScore는 atomic fact 단위 검증을 택한다([ALCE](https://aclanthology.org/2023.emnlp-main.398/), [FActScore](https://aclanthology.org/2023.emnlp-main.741/)).

각 claim에 최소 다음을 추가한다.

- frozen `source_sha256`, byte/line span, excerpt hash, `retrieved_at`/`valid_at`.
- atomic claim과 `assertion_mode`: `observed`, `imported`, `user`, `inferred`, `predicted`.
- verdict: `entailed`, `contradicted`, `insufficient`, `conflict`, `unverifiable`.
- verifier/tool/model tuple, 독립 관찰 group, human receipt.
- semantic mutation: real line/wrong claim, negation, modality, number, entity swap, stale/swapped source, same-origin mirror.

따라서 `trace.json`은 canonical **claim/evidence ledger**이지 자동 truth oracle이 아니다.

## 5. OpenCode 기본 기능을 enforcement로 과대평가한다

공식 [configuration 문서](https://opencode.ai/docs/config/)와 `v1.18.3` [config source](https://github.com/anomalyco/opencode/blob/v1.18.3/packages/opencode/src/config/config.ts)에 따르면 config는 병합된다. `OPENCODE_CONFIG_DIR` 또는 `--pure`만으로 격리됐다고 볼 수 없다. disposable HOME/XDG, neutral CWD, provider allowlist, inherited sentinel, resolved exact-set이 필요하다.

- `small_model`은 `sensai-evidence-peer`를 생성하지 않는다.
- command의 `subtask: true`는 child session일 뿐 peer model/permission이 자동 선택되지 않는다. [task source](https://github.com/anomalyco/opencode/blob/v1.18.3/packages/opencode/src/tool/task.ts)
- compaction은 lossy summary다. mission recovery가 아니다. [compaction source](https://github.com/anomalyco/opencode/blob/v1.18.3/packages/opencode/src/session/compaction.ts)
- `/resume`은 OpenCode session 선택이지 fingerprint-bound mission resume가 아니다.
- static permission glob은 active mission을 동적으로 묶지 못하고, `mmdc` subprocess 쓰기는 edit permission 밖이다.
- todo는 UX view이며 DAG, hard gate, single-writer를 강제하지 않는다.

결론: OpenCode는 UI/orchestration shell로 사용하고, 상태 전이·경로·hash·receipt는 독립 CLI가 강제해야 한다.

## 6. 모델·runtime tuple이 미입학이다

[Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)와 [Qwen3.5-9B](https://huggingface.co/Qwen/Qwen3.5-9B)는 정확한 모델 카드가 있지만, 모델명만으로 OpenCode tool calling을 보장하지 않는다. vLLM의 [tool calling](https://docs.vllm.ai/en/stable/features/tool_calling/)과 [structured output](https://docs.vllm.ai/en/latest/features/structured_outputs/), Ollama의 [OpenCode integration](https://docs.ollama.com/integrations/opencode)과 [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)는 각각 별도 runtime 계약이다.

현재 canonical lead는 `zai/glm-5.2`, peer만 `qwen3.5:9b`다([PROD.md:27-36](../docs/PROD.md#L27-L36)). 따라서 Qwen3.6/vLLM lead 경로는 `DEFERRED_NOT_IN_CANONICAL_TUPLE`로 두고, 정확한 model/runtime/template/parser/context/quantization/hardware tuple마다 admission한다. PRD의 sampling 값은 공식 카드와도 다르므로 calibration 대상이지 기본 사실이 아니다.

## 7. Windows 목표는 현재 제품 출시에 부적합하다

Microsoft의 [Windows release 정보](https://learn.microsoft.com/en-us/windows/release-health/release-information)에 따르면 Windows 10 22H2 일반 지원은 2025-10-14 종료됐다. ESU는 별도 프로그램이며 [lifecycle FAQ](https://learn.microsoft.com/en-us/lifecycle/faq/extended-security-updates)를 따른다. PowerShell 7.6 LTS는 [PowerShell lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/powershell)상 shell 지원이지 OS 지원 복구가 아니다.

vLLM은 [GPU installation 문서](https://docs.vllm.ai/en/v0.22.0/getting_started/installation/gpu/)상 native Windows 경로가 아니고, Ollama는 [Windows 문서](https://docs.ollama.com/windows)상 Win10 22H2 이상을 요구하더라도 실제 context는 hardware에 달린다. 따라서 Windows는 local build blocker가 아니라 **release fingerprint에 결합된 native user receipt**로만 판정한다. 제품 목표는 Windows 11 지원으로 재검토하고 Windows 10은 ESU 고객의 제한적 compatibility lane으로 내려야 한다.
