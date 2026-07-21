# 하네스 release 계약

## release 상태는 세 축이다

| label | 의미 | 독립 조건 |
| --- | --- | --- |
| `LOCAL_IMPLEMENTATION_PASS` | macOS deterministic source/runtime/preflight가 current hash에서 통과 | 모델·Windows를 포함하지 않음 |
| `MODEL_ADMISSION_UNVERIFIED` | live model response/tool-use 입학 미완료 | alias discovery/load와 별도 |
| `WINDOWS_TEST_UNAVAILABLE` | 현재 환경에 Windows 네이티브 테스트 호스트가 없음 | local PASS를 차단하지 않음 |
| `MACOS_STATIC_SUBSTITUTE_PASS` | 현재 payload·설정·경로·quoting·checksum의 macOS 결정적 대체 검사가 통과 | Windows 호환성 승인과 별도 |
| `WINDOWS_COMPATIBILITY_UNVERIFIED` | Windows direct CLI와 OpenCode 연동의 native receipt 없음 | cross-build metadata와 별도 |

local release 후보는 첫 label이 실제 성립할 때만 만들 수 있다. binary나 Markdown에 PASS 문자열을 적는 것 자체는 증거가 아니다.

`LOCAL_IMPLEMENTATION_PASS`는 36개 managed config leaf의 기존 global root 설치, 별도 CLI, project/global runtime overlay, core와 AS-IS 결정적 경로까지의 로컬 구현 상태다. `sensai-dataflow-chart`, `sensai-user-story`, `sensai-requirement-analyze`, `sensai-change-design`, `sensai-test-scenario`는 `VALUE_PROVEN` 전 exact deny이며 live F3-F5 성공은 `MODEL_ADMISSION_UNVERIFIED` 축에 남는다.

## local release 후보

local release 후보는 다음을 포함한다.

- root literal manifest가 가리키는 `output/` source payload 36개
- 한국어 사람용 설명·표시명과 원형이 보존된 기계 key/ID/path/enum/문법
- `go.mod`, `cmd/sensai/`, 사용 문서와 exact Go `1.26.5` build identity
- exact Go `1.26.5`와 같은 source revision에서 생성해 함께 commit한 tracked `bin/sensai`, `bin/sensai.exe`; source mode는 platform별 exact `<source>/bin/` 위치를 사용한다.
- OpenCode `1.18.3`와 tool identity 기록
- `output/` source/stage payload exact-set, checksum, normalized archive metadata
- existing global config의 unmanaged 보존, byte-equal no-op, conflict refusal와 rollback receipt
- project `.sensai/{schemas,recipes}` absent-only override/fallback와 installed CLI provenance receipt
- current preflight와 cleanup receipt
- 모델 및 Windows 외부 상태

secret, raw model transcript, `.omo`, git metadata, runtime mission output, fixture 실행 상태, 외부 symlink target, 사용자 global config의 unmanaged content는 포함하지 않는다. `dist/`가 있더라도 ignored·noncanonical local scratch이므로 release 후보나 전달 목록에 포함하지 않는다.

## Windows 네이티브 테스트 경계

현재 저장소에는 Windows 테스트 환경이 없으므로 네이티브 상태는 `TEST_UNAVAILABLE`, 호환성은 `WINDOWS_COMPATIBILITY_UNVERIFIED`다. macOS에서는 `windows/amd64` artifact의 module metadata와 PE32+ x86-64 형식까지만 확인한다. 이를 Windows direct CLI나 OpenCode 실행 증거로 승격하지 않는다.

향후 실제 Windows receipt를 받는 경우 최소 다음을 가져야 한다.

- OS, terminal, OpenCode, 필수 CLI product/version
- `sensai.exe`와 전달 bundle의 SHA-256
- direct `sensai.exe`의 help, doctor, stage, isolated install, mission case와 exit
- `%USERPROFILE%` 경로와 symlink·junction·기타 reparse point 거부 결과
- temp, environment, process, port cleanup
- 실행 시각과 release fingerprint

현재 native receipt 절차는 발행하지 않는다. 향후 canonical 증명은 exact `<source>\bin\sensai.exe` 또는 `%USERPROFILE%\.local\bin\sensai.exe`를 직접 호출해야 한다. `output/commands/`의 extension 없는 Unix binding은 변경하지 않았으므로 Windows OpenCode slash-command integration은 Scope OUT이다. macOS 대체 검사는 Windows compatibility PASS를 만들 수 없다.

## publication 금지

승인되지 않은 tag, PR, upload, package registry publication을 수행하지 않는다. release acceptance는 실제 사용자 HOME을 mutation하지 않고 disposable HOME에서 global install topology를 검증한다. local archive도 publish가 아니며 source와 receipt hash로만 식별한다.

## 실패와 퇴출

checksum drift, missing/extra payload, stale receipt, false case count, unclean environment, model admission 실패, Windows receipt 실패는 각각 해당 축만 실패시킨다. 더 강한 종합 성공으로 축약하지 않는다. 회귀 시 기존 archive를 덮어쓰지 않고 새 fingerprint로 다시 생성한다.
