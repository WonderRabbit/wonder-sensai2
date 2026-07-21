# 저장소 기여 지침

## 프로젝트 구조 및 모듈 구성

이 저장소는 `wonder-sensai` OpenCode 하네스의 명세, packaging source, stdlib-only Go CLI source와 두 tracked 전달 artifact를 관리한다. `output/`은 설치 payload 36개의 유일한 source root이지만 runtime 탐색 root는 아니다. source checkout은 `cmd/sensai/`, `go.mod`, macOS `bin/sensai`, Windows `bin/sensai.exe`를 포함한다. 루트 `AGENTS.md`는 저장소 기여자 계약이며 runtime prompt가 아니다. `fixtures/`, `tests/`, `cmd/`, `bin/`, `docs/`, 루트 `manifest.txt`는 repository-side 자산으로 `output/`에 복사하지 않는다. `README.md`는 목표 워크플로와 근거 계약을 정의하고, `docs/PROD.md`에는 제품 경계와 Go 도입 게이트가 있으며, `docs/PRD-bin-artifact-delivery.md`에는 binary rebuild·commit·push 계획이 있다. `docs/r4-mapping.md`에는 작업·에이전트·도구 매핑이 있다. 연구 기록은 `docs/research/EXP-template.md`를 기준으로 작성한다. `.gitignore`에 포함된 `plan/`은 로컬 계획 자료이므로 커밋되는 문서가 이 경로에 의존하지 않게 한다.

## 빌드, 테스트 및 개발 명령

현재 체크아웃에는 실행 가능한 fail-closed 테스트 러너가 있다. artifact를 갱신할 때는 exact Go `1.26.5` system binary 또는 task-local Go binary로 현재 source를 exact tracked path `bin/sensai`와 `bin/sensai.exe`에 build한다. packaging source는 `output/`, installed config는 격리한 platform home의 `.config/opencode`, CLI는 격리한 Unix `.local/bin/sensai` 또는 Windows `.local/bin/sensai.exe`에서 검사한다. `dist/`를 사용한다면 ignored·noncanonical local scratch로만 사용하고 최종 전달물이나 commit 대상으로 취급하지 않는다.

```sh
jq empty output/opencode.json
SENSAI_GO="${SENSAI_GO:-go}" # system 또는 task-local exact Go 1.26.5
test "$("$SENSAI_GO" version | awk '{print $3}')" = go1.26.5
mkdir -p bin
env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 "$SENSAI_GO" build -trimpath -o bin/sensai ./cmd/sensai
env CGO_ENABLED=0 GOOS=windows GOARCH=amd64 "$SENSAI_GO" build -trimpath -o bin/sensai.exe ./cmd/sensai
./tests/test.sh self
./tests/test.sh docs
./tests/test.sh fixtures
./tests/test.sh catalog-oracle
./tests/test.sh core-readiness
git diff --check
```

root `manifest.txt`와 Go CLI source는 구현돼 있다. `cmd/sensai/`와 `go.mod`가 동작과 재현의 semantic authority이고, tracked `bin/sensai`와 `bin/sensai.exe`는 그 source에서 생성한 전달 artifact다. artifact는 직접 수정하지 않고 source 변경 뒤 두 target을 함께 재생성한다. `stage`는 부재한 절대 target에 36개 config leaf만 투영하고 `install`은 인자를 받지 않는다. 설치는 managed leaf가 없으면 생성하고 byte-equal regular file이면 no-op이며, differing regular file·symlink·directory 충돌은 쓰기 전에 exit `73`으로 거부한다. 기존 root와 unmanaged content는 보존한다.

## Fixture corpus와 검증 계약

`fixtures/`는 모델이 만드는 임의 예제가 아니라 결정적 검증의 고정 입력과 정답 원장이다. `input/`은 변경하지 않는 legacy·spec·business 입력, `expected/`는 입력에서 검증 가능한 golden 산출, `adversarial/`은 반드시 거부해야 하는 오류·충돌·경로·가짜 secret 사례다. 모든 `expected/` 근거 ID는 canonical trace의 ID와 `path:line` provenance로 역참조돼야 하며, synthetic marker와 가짜 secret은 산출물·로그·evidence로 전파하면 안 된다.

`fixtures/FILES.txt`는 metadata를 제외한 물리 leaf 35개를 정렬·중복 없이 고정한다. 실제 물리 exact-set은 이 35개와 `FILES.txt`, `SHA256SUMS`를 합친 37개다. `SHA256SUMS`는 `FILES.txt`의 35개와 `FILES.txt` 자체, 총 36개를 lowercase SHA-256과 정확한 두 칸 구분자로 보호한다. `CASES.json`은 happy 14개와 adversarial 14개를 각각 예상 exit/reason과 연결한다. `./tests/test.sh fixtures`는 exact-set, hash, 14/14 대칭, provenance, dangling ID, synthetic marker 비전파를 검사하고, `./tests/test.sh expect-fail fixture-without-golden`은 격리 복사본의 의도한 semantic failure만 인정한다. 원본 fixture는 mutation하지 않으며 모든 mutation은 임시 복사본에서만 수행한다.

fixture를 하나라도 바꾸면 다음 순서 전체를 수행한다.

1. metadata를 제외한 모든 leaf를 `fixtures/FILES.txt`에 다시 나열하고 `LC_ALL=C sort -u` 결과가 정확히 35개인지 확인한다.
2. `FILES.txt` 순서의 각 파일과 `FILES.txt` 자체를 `shasum -a 256`으로 다시 계산하고 정렬해 `fixtures/SHA256SUMS`를 교체한다.
3. `fixtures/CASES.json`의 입력·golden·예상 exit/reason과 14 happy/14 adversarial 대칭을 갱신한다.
4. `./tests/test.sh fixtures`, `./tests/test.sh expect-fail fixture-without-golden`, `./tests/test.sh self`, `./tests/test.sh docs`를 모두 실행하고 새 evidence receipt를 남긴다.

## 코딩 스타일 및 이름 규칙

파일에서 다른 언어를 요구하지 않는 한 문서는 간결한 한국어로 작성한다. ATX 제목, 언어가 지정된 코드 펜스, 경로와 식별자를 위한 백틱, `| --- |` 구분선을 사용하는 Markdown 표를 따른다. 요구사항 ID와 상태 값의 철자를 임의로 바꾸지 않는다. 설명형 파일명은 `r4-mapping.md`처럼 kebab-case를 사용하고, 연구 기록 ID는 `EXP-YYYYMMDD-NNN` 형식을 따른다. JSON은 공백 두 칸으로 들여쓴다. 현재 P0 설계는 stdlib-only Go CLI와 독립 검증 도구를 사용하므로 Node/TypeScript 런타임 의존성을 추가하지 않는다.

`output/` 아래에서 사람이 읽는 제목, 설명, 지침, provider/model 표시명은 한국어로 작성한다. OpenCode가 요구하는 key와 schema field, provider/model ID, 경로, command/skill 이름, stable ID, enum, reason code, shell·JSON·jq 문법은 번역하지 않고 정확히 보존한다. 기계 식별자를 한국어화하거나 영어 자연어 설명을 output에 남기는 변경은 모두 실패다.

## 테스트 지침

명령 예제와 상대 링크를 직접 검토한 뒤 위 검사를 실행한다. 근거 규칙 변경은 명시적인 미확인, 모호성, 충돌, `path:line` provenance 상태를 보존해야 한다. 실행 자산을 추가할 때는 `tests/` 아래에 happy, adversarial, regression 시나리오를 만들고 정확한 실행법을 `README.md`에 기록한다. config manifest exact-set 계약은 `tests/contracts/`가 소유하며 36개 managed leaf와 별도 installed CLI를 하나의 root로 합치지 않는다.

## 커밋 및 Pull Request 지침

현재 브랜치에는 커밋이 없어 기존 메시지 규칙을 추론할 수 없다. `docs: Go 도입 게이트 명확화`처럼 범위가 분명한 짧은 명령형 제목을 사용하고, 커밋 하나에는 한 가지 목적만 담는다. Pull Request에는 문제와 결정, 영향받는 문서나 요구사항 ID, 검증 결과를 적고 관련 이슈가 있으면 연결한다. Mermaid 등 시각 산출물의 렌더 결과를 검토할 때만 스크린샷을 첨부한다.

## 보안 및 설정 주의사항

자격 증명, 모델 토큰, `.env` 파일, 장비별 절대 경로를 커밋하지 않는다. 실험은 전역 OpenCode 설정과 격리하고, 저장소 텍스트와 모델 출력은 결정적 도구가 검증하기 전까지 신뢰하지 않는다.
