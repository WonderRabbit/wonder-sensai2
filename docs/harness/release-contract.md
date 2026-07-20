# 하네스 release 계약

## release 상태는 세 축이다

| label | 의미 | 독립 조건 |
| --- | --- | --- |
| `LOCAL_IMPLEMENTATION_PASS` | macOS deterministic source/runtime/preflight가 current hash에서 통과 | 모델·Windows를 포함하지 않음 |
| `MODEL_ADMISSION_UNVERIFIED` | live model response/tool-use 입학 미완료 | alias discovery/load와 별도 |
| `WINDOWS_TEST_UNAVAILABLE` | 현재 환경에 Windows 네이티브 테스트 호스트가 없음 | local PASS를 차단하지 않음 |
| `MACOS_STATIC_SUBSTITUTE_PASS` | 현재 payload·설정·경로·quoting·checksum의 macOS 결정적 대체 검사가 통과 | Windows 호환성 승인과 별도 |

release archive는 첫 label이 실제 성립할 때만 만들 수 있다. archive나 Markdown에 PASS 문자열을 적는 것 자체는 증거가 아니다.

`LOCAL_IMPLEMENTATION_PASS`는 설치 CLI, core와 AS-IS 결정적 경로까지의 로컬 구현 상태다. `sensai-dataflow-chart`, `sensai-user-story`, `sensai-requirement-analyze`, `sensai-change-design`, `sensai-test-scenario`는 `VALUE_PROVEN` 전 exact deny이며 live F3-F5 성공은 `MODEL_ADMISSION_UNVERIFIED` 축에 남는다.

## local release 후보

local release 후보는 다음을 포함한다.

- root literal manifest가 가리키는 `output/` source payload
- 한국어 사람용 설명·표시명과 원형이 보존된 기계 key/ID/path/enum/문법
- repo-side installer와 사용 문서
- OpenCode `1.18.3`와 tool identity 기록
- `output/` source/stage payload exact-set, checksum, normalized archive metadata
- current preflight와 cleanup receipt
- 모델 및 Windows 외부 상태

secret, raw model transcript, `.omo`, git metadata, runtime mission output, fixture 실행 상태, 외부 symlink target은 포함하지 않는다.

## Windows 네이티브 테스트 경계

현재 저장소에는 Windows 테스트 환경이 없으므로 네이티브 상태는 `TEST_UNAVAILABLE`, 호환성은 `UNVERIFIED`다. macOS 대체 검사는 현재 payload exact-set, OpenCode 설정 projection, POSIX 경로와 quoting, manifest checksum만 다루며 PowerShell kit는 T29에서 별도로 구현한다. 대체 검사를 Windows 실행 증거로 승격하지 않는다.

향후 실제 Windows receipt를 받는 경우 최소 다음을 가져야 한다.

- OS, PowerShell, OpenCode, 필수 CLI product/version
- release archive와 kit SHA-256
- doctor, stage, isolated load, deterministic test의 case와 exit
- temp, environment, process, port cleanup
- 실행 시각과 release fingerprint

현재 kit는 존재하지 않으므로 정확한 사용자 명령을 아직 발행하지 않는다. kit가 구현된 뒤 문서화된 `pwsh -File ...` 명령만 canonical 명령이 된다. macOS 대체 검사는 Windows compatibility PASS를 만들 수 없다.

## publication 금지

승인되지 않은 tag, PR, upload, package registry publication, 실제 전역 OpenCode 설치를 수행하지 않는다. local archive도 publish가 아니며 source와 receipt hash로만 식별한다.

## 실패와 퇴출

checksum drift, missing/extra payload, stale receipt, false case count, unclean environment, model admission 실패, Windows receipt 실패는 각각 해당 축만 실패시킨다. 더 강한 종합 성공으로 축약하지 않는다. 회귀 시 기존 archive를 덮어쓰지 않고 새 fingerprint로 다시 생성한다.
