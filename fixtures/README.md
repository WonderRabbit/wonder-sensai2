# Fixture corpus contract

이 디렉터리는 실행 runtime이 아니라 불변 입력·골든·대립 자료다. 모든 경로는 이 디렉터리 기준 상대 경로다.

- `CASES.json`은 exact 14 happy / 14 adversarial case와 각 exit·reason을 소유한다.
- happy case는 `inputs`, `expected_artifacts`, `provenance`를 가지며 각 골든 안에 실제 `path:line` 문자열이 있어야 한다.
- `adversarial/malformed.json`만 의도적으로 JSON 문법이 깨져 있다. 그 외 JSON과 YAML은 파싱되어야 한다.
- `FILES.txt`는 `FILES.txt`와 `SHA256SUMS`를 제외한 모든 불변 leaf를 정렬된 exact-set으로 나열한다.
- `SHA256SUMS`는 `FILES.txt`의 각 경로와 `FILES.txt` 자체만 해시하며 자기 자신을 해시하지 않는다.
- 모든 leaf는 일반 파일이고 symlink, FIFO, lock, 개행 경로, traversal 경로는 테스트가 `mktemp` 아래에서만 만든다.
- `.tsx`와 `.java`는 fixture source일 뿐 실행하지 않는다. package manifest, lockfile, 실행 비트, fixture runtime을 추가하지 않는다.
- `inputs/secrets/fake-secret.txt`는 명확히 합성된 canary다. 실제 자격 증명이 아니며 emitted artifact, evidence, receipt에 원문을 복사하지 않는다.
