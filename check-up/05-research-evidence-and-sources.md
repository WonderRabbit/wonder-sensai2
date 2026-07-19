# 연구 근거와 출처

## 로컬 실행 근거

| 근거 | 결과 | 효력 |
| --- | --- | --- |
| `jq empty opencode.json` | exit 0 | JSON syntax만 확인 |
| `self` | PASS, 30 assertions | runner bootstrap |
| `docs` | PASS, 185 assertions | source/planning 문서 계약 |
| `fixtures` | PASS, 68 assertions | fixture corpus integrity |
| `core-readiness` | exit 1, 7/8 failure | runtime core 부재의 정상 RED |
| 세 expected-failure selector | 모두 exit 0 | named semantic failure 검출 |
| fake surface root | `core-readiness` false PASS | presence-only readiness의 반증 |
| Git | unborn HEAD, source untracked | current receipt에 all-file fingerprint 필요 |

검증 command와 기대 의미는 [README.md:95-110](../README.md#L95-L110), runner selector는 [tests/test.sh:14-27](../tests/test.sh#L14-L27), readiness의 한계는 [core-readiness.sh:3-18](../tests/cases/core-readiness.sh#L3-L18)에서 확인할 수 있다.

## 1차 출처

### OpenCode

- [Configuration](https://opencode.ai/docs/config/) — config locations와 merge semantics.
- [CLI](https://opencode.ai/docs/cli/), [Commands](https://opencode.ai/docs/commands/) — 사용자 명령·session surface.
- [v1.18.3 config source](https://github.com/anomalyco/opencode/blob/v1.18.3/packages/opencode/src/config/config.ts) — pinned implementation.
- [v1.18.3 task source](https://github.com/anomalyco/opencode/blob/v1.18.3/packages/opencode/src/tool/task.ts) — child session task semantics.
- [v1.18.3 compaction source](https://github.com/anomalyco/opencode/blob/v1.18.3/packages/opencode/src/session/compaction.ts) — lossy summary path.

프로젝트 결론: OpenCode는 shell/UI로 적합하지만 mission state machine과 filesystem safety의 판정자는 아니다.

### 모델과 serving

- [Qwen3.6-35B-A3B model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- [Qwen3.5-9B model card](https://huggingface.co/Qwen/Qwen3.5-9B)
- [vLLM tool calling](https://docs.vllm.ai/en/stable/features/tool_calling/)
- [vLLM structured outputs](https://docs.vllm.ai/en/latest/features/structured_outputs/)
- [Ollama OpenCode integration](https://docs.ollama.com/integrations/opencode)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)

프로젝트 결론: model alias, context length, tool parser, template, structured output, serving runtime, hardware를 한 tuple로 admission한다. 현재 Qwen 값은 미입학이다.

### provenance와 factuality

- W3C [PROV-DM](https://www.w3.org/TR/prov-dm/), [PROV-CONSTRAINTS](https://www.w3.org/TR/prov-constraints/), [PROV-AQ](https://www.w3.org/TR/prov-aq/)
- [ALCE](https://aclanthology.org/2023.emnlp-main.398/) — citation correctness/completeness/style 분리.
- [FActScore](https://aclanthology.org/2023.emnlp-main.741/) — atomic fact 단위 factual precision.
- [RFC 8785 JCS](https://www.rfc-editor.org/rfc/rfc8785) — JSON canonicalization.

프로젝트 결론: provenance integrity, claim entailment, source quality/freshness/independence를 별도 verdict로 둔다.

### legacy 이해와 impact 분석

- [Symphony reconstruction process](https://repository.tudelft.nl/file/File_395a9168-46c2-474c-9d48-eff6d2975287)
- [Reflexion model case study](https://www.cs.ubc.ca/~murphy/papers/rm/rm-case-study.pdf)
- [ISO/IEC/IEEE 42010 overview](https://www.iso.org/standard/74393.html)
- [Chianti change impact analysis](https://www.franktip.org/pubs/oopsla2004.pdf)
- [From COBOL to Business Rules](https://research.vu.nl/ws/files/231254036/From_COBOL_to_Business_Rules_Extracting_Business_Rules_from_Legacy_Code.pdf)

프로젝트 결론: render 성공보다 maintainer task, semantic precision/recall, change-impact recall/precision, business-rule technical negatives와 SME agreement를 측정한다.

### Windows

- Microsoft [Windows release information](https://learn.microsoft.com/en-us/windows/release-health/release-information)
- Microsoft [Extended Security Updates FAQ](https://learn.microsoft.com/en-us/lifecycle/faq/extended-security-updates)
- Microsoft [PowerShell lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/powershell)
- [vLLM GPU installation](https://docs.vllm.ai/en/v0.22.0/getting_started/installation/gpu/)
- [Ollama for Windows](https://docs.ollama.com/windows)

프로젝트 결론: Win10/PS7.6 문서 선언은 지원 증거가 아니다. current release를 native Windows에서 실행한 receipt만 효력이 있다.

## 조사 한계

- live model call, OpenCode TUI session, native Windows 실행은 수행하지 않았다. 모두 `UNVERIFIED`다.
- external URL은 2026-07-19 조사에서 primary source로 채택했지만 release 전 pinned version/archived snapshot을 receipt에 남겨야 한다.
- pilot threshold는 calibration이며 3명 결과를 시장 전체로 일반화하지 않는다.
