# CI/CD 운영 기준

[← README](../README.md)

이 문서는 OT Cooling CRM에서 실제로 구현 · 운영한 GitHub Actions 검증 흐름을 기준으로 작성했습니다.
PR을 검토하거나 배포 방식을 논의할 때, **어디까지 자동화되어 있고 무엇을 사람이 직접 하는지**를 확인하는 용도입니다.

---

## 1. 기본 원칙

> **Git은 기록용이다. 어떤 org에도 자동으로 배포하지 않는다. 실제 배포는 org에서 직접 수행한다.**

`main`으로 PR이 올라오면 Production org를 대상으로 변경분을 **검증(dry-run)만** 합니다.
검증은 "이 변경을 실제로 올리면 배포가 되는가"를 확인할 뿐, org를 바꾸지 않습니다.

```
기능 브랜치 작업
      ↓
main 대상 PR 생성
      ↓
GitHub Actions 자동 검증 (verify)
      ↓
검증 통과 시 자동 병합 (auto-merge)
      ↓
org 반영은 별도로 직접 수행
```

---

## 2. 워크플로 구성

워크플로 이름 — **`Main 검증 (Production org 대조)`**

### 실행 조건

| | |
| --- | --- |
| 이벤트 | `main` 대상 pull request |
| 경로 필터 | `force-app/**` · `.github/workflows/**` |

두 경로 밖의 변경(문서 등)만 있는 PR에서는 워크플로가 실행되지 않습니다.

### `verify` job

| 단계 | 수행 내용 |
| --- | --- |
| 코드 체크아웃 | `fetch-depth: 0` — delta 계산에 전체 히스토리가 필요 |
| 환경 준비 | Node.js 22 · Salesforce CLI · sfdx-git-delta 플러그인 |
| org 인증 | `SFDX_PRODUCTION_URL` Secret으로 Production org 로그인 |
| 변경 메타데이터 추출 | `origin/main` 대비 delta 생성 — 이번 PR의 변경분만 |
| 배포 검증 | `--dry-run`으로 배포 가능 여부 확인 (아래 테스트 게이트 참조) |
| 삭제 메타데이터 검증 | `destructiveChanges.xml`이 있으면 삭제도 dry-run으로 검증 |

### `auto-merge` job

`verify`가 통과하면 `gh pr merge --merge --auto`로 PR을 병합합니다.
**병합은 자동이지만 배포는 자동이 아닙니다.** merge commit 방식이라 커밋 이력이 보존됩니다.

### 필수 Secret

| Secret | 용도 |
| --- | --- |
| `SFDX_INTEGRATION_URL` | Actions의 org 인증. SFDX Auth URL 전체를 저장하며 코드 · PR · 로그에 노출하지 않는다 |

---

## 3. 테스트 게이트

Apex 변경 여부에 따라 테스트 실행 방식이 달라집니다.

```
델타에 .cls 또는 .trigger 가 있는가?
├─ 예 ─┬─ 델타에 *Test.cls 가 있는가?
│      ├─ 예    → RunSpecifiedTests 로 해당 테스트를 지정 실행
│      └─ 아니오 → 경고를 남기고 NoTestRun (구조 검증만)
└─ 아니오 → NoTestRun (배포 검증만)
```

### 왜 `RunLocalTests`가 아니라 `RunSpecifiedTests`인가

**dry-run은 코드를 org에 배포하지 않습니다.** 그래서 `RunLocalTests`를 지정해도 org는 PR에 새로 추가된 테스트 클래스의 존재를 모르고, 결과적으로 새 테스트가 실행되지 않습니다.

이 문제를 피하기 위해 델타에서 `*Test.cls` 파일명을 추출해 `--tests`로 직접 지정합니다.

```bash
TEST_CLASSES=$(find changed-sources/force-app -name "*Test.cls" \
               -exec basename {} .cls \; | paste -sd, -)
```

### 왜 Apex 외 변경에는 테스트 게이트를 걸지 않는가

Permission Set · LWC · Flow 등의 변경은 **실행할 Apex 테스트가 없는 것이 정상**입니다.
여기에 테스트 통과를 강제하면 정상적인 변경이 전부 막힙니다. Apex가 포함된 변경에만 게이트를 적용합니다.

Apex 변경이 있는데 델타에 테스트 클래스가 없으면 실패시키지 않고 **경고를 남기고 구조 검증만** 수행합니다.

---

## 4. 검증은 현재 org 상태를 기준으로 한다

Actions는 다른 열린 PR의 변경사항을 미리 합쳐서 검사하지 않습니다. 검사 시점의 실제 org를 기준으로 해당 PR의 delta만 봅니다.

PR A가 새 필드를 만들고 PR B가 그 필드를 Layout에 배치할 때, A가 org에 반영되지 않은 상태에서 B는 실패할 수 있습니다.
이는 오류라기보다 **B가 A에 의존한다는 사실을 드러내는 정상적인 결과**입니다. PR 순서를 관리할 때 중요한 기준입니다.

---

## 5. 운영 기준

| 상황 | 권장 행동 |
| --- | --- |
| 일반 Salesforce 변경 PR | `main` 대상 PR 생성 → `verify` 통과 확인 → 자동 병합 |
| 검증 실패 | 실패한 단계의 오류 원인을 확인하고 같은 브랜치에 수정 push |
| Apex를 추가 · 수정하는 PR | 대응하는 테스트 클래스를 같은 PR에 포함시킨다 |
| 앞 작업의 필드 · Flow · Layout을 참조하는 PR | 선행 작업의 org 반영 여부를 먼저 확인하거나 순서대로 검증 |
| 문서 · 설정 파일만 바꾸는 PR | 경로 필터 밖이라 워크플로가 실행되지 않는다 |
| Setup UI로만 변경한 설정 | Git 소스로 재현되지 않으므로 org 반영 여부를 별도 관리 |

---

## 6. 왜 실제 배포를 자동화하지 않는가

Salesforce는 **코드만으로 상태가 정해지지 않습니다.** Setup 화면에서 직접 바꾼 설정은 Git에 남지 않습니다.

브랜치와 org의 상태가 어긋난 채로 자동 배포가 돌면, Git에 있는 이전 상태가 org의 최신 작업을 덮어쓸 수 있습니다.
배포는 성공하고, 사라진 작업은 드러나지 않습니다.

**자동화보다 먼저 갖춰져야 하는 것은 서버와 브랜치의 동기화**입니다.

### 배포 자동화를 도입하려면

1. `main`의 소스가 org 상태와 지속적으로 일치해야 한다
2. 필드 · Layout · Flow 등 작업 간 의존성이 PR 순서와 배포 순서로 관리되어야 한다
3. Setup UI에서만 변경하는 설정의 반영 방식을 정해야 한다
4. 삭제 변경의 승인 · 검증 · 롤백 기준을 정해야 한다
5. 환경별 책임과 승인 기준을 정해야 한다

이 조건이 정리되기 전까지는 **자동 검증 + 자동 병합 + 수동 배포**가 더 안전한 운영 방식입니다.
