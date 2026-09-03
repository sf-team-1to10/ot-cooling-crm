# OT전자 CRM — Git / 오그 협업 규칙

> 프로덕션 오그에 여러 계정이 동시 연동되어 작업하면서 발생한 "덮어쓰기" 사고를 막기 위한 팀 공통 규칙.
> 작업 시작 전 반드시 읽고, 애매하면 이 문서 기준으로 판단할 것.

---

## 제1원칙

**Git의 `main`이 유일한 기준(source of truth)이다. 오그는 기준이 아니라 결과물이다.**

오그를 보고 판단해서 배포하거나, 오그 상태끼리 비교해서 "맞다/틀리다"를 정하지 않는다.
흐름은 항상 한 방향: `main → 내 브랜치 → 내 오그(테스트용)`. 반대 방향(오그 → git)은 내가 이번에 작업한 파일에 한해서만 허용.

---

## 브랜치 네이밍

```
feature-[이니셜]-[번호]
```

예: `feature-HJ-4`, `feature-KM-2`

- 이니셜: 담당자 구분용 (기존 관례 유지)
- 번호: 본인 기준 순번 (겹쳐도 무방, 이니셜로 구분됨)
- 하나의 브랜치 = 하나의 작업 단위. 여러 기능을 한 브랜치에 섞지 않는다.

---

## 작업 사이클

### 1) 시작 전
```bash
git checkout main
git pull origin main
git checkout -b feature-[이니셜]-[번호]
```
- 반드시 `main`을 최신화한 뒤 브랜치를 판다 (오래된 main에서 따지 않기)

### 2) 오그에 반영해서 테스트할 때 — 전체 배포 금지
```bash
# 특정 컴포넌트/클래스만 지정해서 배포
sf project deploy start -o [내오그alias] -p force-app/main/default/lwc/[컴포넌트명]
sf project deploy start -o [내오그alias] -p force-app/main/default/classes/[클래스명].cls
```
- `-p` 없이 전체 배포/전체 retrieve 금지. 남의 미완성 변경이 섞여 들어온다.
- 오그에서 뭔가 가져와야 하면(예: Flow Builder로 오그에서 직접 수정한 경우) 그 파일 경로만 콕 집어서 retrieve:
```bash
sf project retrieve start -o [내오그alias] -p force-app/main/default/flows/[Flow명].flow-meta.xml
```

### 3) 커밋 — 파일 골라서 add (`git add .` 금지)
```bash
git status                 # 뭐가 바뀌었는지 먼저 확인
git add [파일경로1] [파일경로2]
git diff --staged          # 스테이징된 내용 재확인
git commit -m "[타입]: [작업 내용 한 줄 요약]"
```
- 타입 예시: `feat`, `fix`, `refactor`, `docs`, `perf`
- 관련 없는 변경(문서, 다른 컴포넌트, 오그 retrieve로 딸려온 파일)은 같은 커밋에 넣지 않는다

### 4) PR 올리기 전 — 반드시 main 최신 반영
```bash
git fetch origin
git rebase origin/main
# 충돌 나면 로컬에서 해결
git add [해결한 파일]
git rebase --continue

git push origin feature-[이니셜]-[번호]
```
- 충돌은 여기서 끝낸다. "오그에 내 걸로 덮어써서" 해결하는 것 금지.

### 5) PR 머지 전 — 검증 필수
```bash
sf project deploy validate -o [프로덕션오그alias] -p force-app/main/default/[변경경로]
```
- check-only 검증 통과 확인 후 머지
- 가능하면 GitHub Actions로 PR마다 자동 실행되도록 설정 (추후 구성)

---

## 충돌 나기 쉬운 항목 — 손대기 전에 공지

같은 파일을 여러 명이 동시에 건드리면 무조건 충돌한다. 아래 유형은 작업 시작 전 팀 채널에 "지금 이거 건드림" 한 줄 공지:

- PermissionSet / Profile
- FlexiPage (레코드 페이지)
- 같은 LWC 컴포넌트 (`otAssetPortal`, `otMyAssets` 등)
- Flow

---

## 하지 말 것 (안티패턴)

| 금지 행동 | 이유 |
|---|---|
| `git add .` / `git add -A` | 무관한 파일·오그 부산물이 같이 커밋됨 |
| `-p` 없이 전체 `deploy`/`retrieve` | 남의 미완성 변경이 내 브랜치에 섞임 |
| 오그 상태 보고 "맞는 버전" 판단 | 오그는 기준이 아님. git이 기준 |
| 오래 묵힌 브랜치 (며칠 이상) | main과 멀어질수록 충돌 커짐. 작게 자주 PR |
| main 직접 push | 반드시 PR 경유 |
| 오그에서 오그로 직접 복사/배포 | 항상 git을 경유 |
| 충돌을 오그 재배포로 "해결" | git에서 먼저 해결 후 배포 |

---

## 체크리스트 (PR 올리기 전 마지막 확인)

- [ ] `main`을 rebase 했는가
- [ ] `git diff --staged`로 무관한 파일이 없는지 확인했는가
- [ ] 충돌 나기 쉬운 항목(PermissionSet 등)을 건드렸다면 팀에 공지했는가
- [ ] `deploy validate` 통과했는가
- [ ] PR 설명에 변경 파일/영향 범위를 명시했는가
