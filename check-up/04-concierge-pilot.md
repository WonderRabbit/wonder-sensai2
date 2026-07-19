# 10영업일 F1 concierge pilot

## 질문

“근거가 결합된 F1 기술 분석이 실제 maintainer의 승인된 변경 판단을 더 빠르고 정확하게 만들며, 다시 사용할 가치가 있는가?”

Mermaid가 렌더되는지, fixture가 예쁘게 나오는지, 모델이 긴 보고서를 쓰는지는 핵심 질문이 아니다.

## 범위

포함:

- 사용자 3명, 서로 다른 실제 repository 3개.
- 각 repo의 최근 승인된 변경 1개와 관련 코드 snapshot.
- 변경 범위의 stack/structure/convention/call path/impact 분석.
- 사람이 수행하는 concierge workflow와 결정적 CLI evidence capture.

제외:

- F2 비즈니스 분석, 전체 F0-F5, TO-BE 생성.
- peer agent, 2/9/15 catalog, installer, resume, packaging.
- live Windows, cross-platform claim, Qwen3.6/vLLM 경로.
- 대상 repository 수정·코드 생성.

## 실험 설계

1. 각 maintainer가 기존 방식으로 같은 유형의 과거 변경을 검토한 baseline 시간과 correction을 확보한다.
2. accepted change와 review discussion을 blind atomic gold로 만든다. pilot 작성자는 gold verdict를 보지 않는다.
3. concierge는 evidence packet을 만든다: atomic claim, source digest/span, verdict, uncertainty, impact candidate.
4. maintainer는 packet으로 change-impact/설계 판단을 수행하고 오류를 수정한다.
5. blind reviewer가 gold와 비교해 critical precision/recall, entailment, fabrication을 판정한다.
6. 마지막에 “다음 실제 작업에서 다시 쓰겠는가?”를 행동 의향으로 기록한다.

## 측정값

| metric | 정의 | calibration gate |
| --- | --- | ---: |
| repeat use | 다음 실제 작업 사용 동의 | `>=2/3` |
| accepted-decision time | 분석 시작→maintainer 승인까지 active human minutes | baseline 대비 `>=30%` 단축 |
| correction rate | 사람이 수정한 atomic claim / 전체 claim | `<=20%` |
| entailment | frozen source span이 claim을 지지 | `>=95%` |
| critical precision | critical로 제시한 claim 중 정답 | `100%` |
| critical recall | gold critical claim 중 회수 | `100%` |
| critical fabrication | 근거 없이 생성된 critical claim | `0` |
| mutation detection | negation/number/entity/stale-source mutation 검출 | `100%` |

소표본 연구는 목적에 맞는 사례 선택과 saturation을 요구하며 숫자만으로 일반화할 수 없다([Guest et al.](https://doi.org/10.1177/1525822X05279903), [Simmons et al.](https://doi.org/10.3758/BF03195514)). 따라서 이 gate는 투자 방향을 정하는 calibration이다.

## 10일 일정

| 일 | 산출 | owner |
| --- | --- | --- |
| 1 | 사용자/repo/change 선정, 동의·비밀정보 경계 | Product owner |
| 2 | baseline 정의, blind gold protocol, criticality rubric | Evidence lead |
| 3-4 | Repo A concierge run + blind review | Analyst + reviewer |
| 5-6 | Repo B run + 첫 failure taxonomy | Analyst + reviewer |
| 7-8 | Repo C run + semantic mutation | Analyst + reviewer |
| 9 | metric 집계, correction/fabrication 원인 분류 | Evidence lead |
| 10 | `GO`/`PIVOT`/`KILL` decision record | Product owner |

## 실행 packet

각 repo마다 다음 파일을 별도 비공개 evidence root에 둔다.

- `scope.json`: repo/revision/scope/exclusions/tool identities.
- `source-manifest.json`: canonical path + raw SHA-256.
- `claims.json`: atomic claim, source span/hash, assertion mode, verdict.
- `impact.md`: maintainer가 읽는 짧은 결과.
- `review.json`: blind gold comparison과 correction.
- `timing.json`: active human minutes와 중단 시간 분리.
- `decision.json`: repeat-use 답, gate 결과, 이유.

## 판정

- `GO`: 모든 safety/quality gate와 repeat-use/time gate 통과. Phase B evidence kernel만 승인.
- `PIVOT`: critical safety는 통과하지만 adoption/time 중 하나 실패. 출력 범위·사용자 segment를 한 번 바꿔 재실험.
- `KILL`: critical fabrication 발생, critical recall 실패, 또는 같은 gate가 수정 후 두 번 실패.

pilot 성공도 전체 제품 GO가 아니다. 다음 투자 단위는 evidence kernel 하나다.
