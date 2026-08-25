# Asset.Frequency__c → Asset.Maintenance_Frequency__c 필드 정정 — destructive 실행 안내

## 왜 2단계인가
Salesforce는 `fullName`을 바꾼 필드 XML을 배포하면 **rename이 아니라 새 필드 추가**로 처리한다. 기존 `Frequency__c`는 org에 그대로 남는다.
이 PR 자체(force-app 변경분)는 새 필드 생성 + 참조 3곳(Flow·PermissionSet·`Next_Inspection_Date__c` 설명) 전환만 담고 있다 — **여기까지는 안전하고 dry-run 검증 완료**.

`Frequency__c` 실제 삭제는 이 폴더의 매니페스트로 **별도 실행**해야 한다. CI(`pr-develop-branch.yml`)는 `force-app/**` 경로만 감시하므로 이 폴더는 **자동으로 실행되지 않는다** — 반드시 사람이 `sf project deploy start --manifest manifest/destructive/package.xml --post-destructive-changes manifest/destructive/destructiveChangesPost.xml` 명령을 직접 실행해야 한다.

## 실행 전 반드시 확인할 것 (순서대로)

1. **이 PR의 force-app 변경분이 먼저 merge·배포돼 있어야 한다.** (새 필드 + Flow가 새 필드를 참조하도록 전환된 상태)
2. **`Frequency__c`에 실제 데이터가 있는지 확인.** 이 세션에서는 describe-cache 지연(Tooling API로는 필드가 보이는데 SOQL은 `INVALID_FIELD`를 반환하는 현상, 이 프로젝트에서 반복 관찰된 패턴)으로 값 존재 여부를 확인하지 못했다. Setup UI(Object Manager → Asset → Fields → Frequency__c → 관련 리스트/사용 현황) 또는 캐시가 풀린 뒤 SOQL로 재확인 필요. **값이 있으면 삭제 전에 `Maintenance_Frequency__c`로 이관하는 별도 작업 필요.**
3. **옛 Flow 버전이 여전히 `Frequency__c`를 참조하는지 확인.** dry-run 검증 중 활성 Flow 버전(`301h8000000tWp0`, V1)이 옛 필드를 참조해 삭제가 거부되는 걸 확인했다. 이 PR의 Flow 변경분이 배포되면 새 활성 버전(V2)이 생기지만, **비활성 구버전(V1)이 org에 남아 여전히 참조를 붙들 수 있다** — Setup → Flows → 해당 Flow → Version History에서 구버전을 먼저 삭제해야 할 수 있다.
4. 위 두 가지가 정리된 뒤에만 아래 명령 실행.

## 실행 명령 (사람이 직접, 대상 org 확인 후)

```
sf project deploy start \
  --manifest manifest/destructive/package.xml \
  --post-destructive-changes manifest/destructive/destructiveChangesPost.xml \
  --target-org <배포 대상 org>
```

## 이 폴더가 하는 일

- `package.xml`: 최종 상태 확인용(새 필드 + 참조 3곳) — 실제로는 force-app 배포로 이미 반영됨, 이 매니페스트 자체를 다시 돌릴 필요는 없음
- `destructiveChangesPost.xml`: `Asset.Frequency__c` 삭제 대상 지정 — **post**이므로 위 package.xml 배포 이후 순서로 실행되도록 설계됨(Salesforce 표준 rename 패턴)
