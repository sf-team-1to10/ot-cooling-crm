#!/usr/bin/env bash
# T4-08 화면·FLS 배포 — 프리플라이트(org 필드 존재 대조) 통과 시에만 배포
set -euo pipefail
ORG=T4OPS
BASE=force-app/main/default
FLEXI=$BASE/flexipages/WorkOrderLineItem_Record_Page.flexipage-meta.xml
PS=$BASE/permissionsets/PS_Service.permissionset-meta.xml

echo "== 1. org 필드 목록 (Tooling API — FLS 무관하게 실제 존재 여부) =="
# describe는 현재 사용자 FLS 기준이라 FLS 미부여 필드를 숨긴다. Tooling API의 CustomField로 확인.
sf data query -o $ORG --use-tooling-api --json \
  -q "SELECT TableEnumOrId, DeveloperName FROM CustomField WHERE TableEnumOrId IN ('WorkOrder','WorkOrderLineItem')" \
  > /tmp/woli_cf.json

python3 - "$FLEXI" "$PS" <<'EOF'
import json,re,sys
flexi,ps=sys.argv[1],sys.argv[2]
# Tooling CustomField.DeveloperName 은 __c 없는 이름 → org[obj] = {DeveloperName + '__c'}
rows=json.load(open('/tmp/woli_cf.json'))['result']['records']
org={'WorkOrder':set(),'WorkOrderLineItem':set()}
for r in rows:
    t=r['TableEnumOrId']
    if t in org: org[t].add(r['DeveloperName']+'__c')
# 표준 필드는 프리플라이트 대상이 아님 (Record.Status 등) → __c 로 끝나는 참조만 검사
missing=[]
for f in sorted(set(re.findall(r'<fieldItem>Record\.([A-Za-z0-9_]+)</fieldItem>',open(flexi).read()))):
    if f.endswith('__c') and f not in org['WorkOrderLineItem']: missing.append(f'FlexiPage WOLI.{f}')
for o,f in re.findall(r'<field>([A-Za-z]+)\.([A-Za-z0-9_]+)</field>',open(ps).read()):
    if o in org and f.endswith('__c') and f not in org[o]: missing.append(f'PS_Service {o}.{f}')
print("== 2. 프리플라이트 (Tooling API) ==")
if missing:
    print("❌ org에 없는 참조 %d건 — 배포 중단"%len(missing)); [print("   ",m) for m in missing]; sys.exit(1)
print("✅ 참조 커스텀 필드 전부 org에 존재")
EOF

echo "== 3. 배포 (WO Record Page 제외) =="
sf project deploy start -o $ORG \
  -m PermissionSet:PS_Service \
  -m FlexiPage:WorkOrderLineItem_Record_Page \
  -m CustomObject:WorkOrderLineItem

echo "== 4. FLS 실효 증명: PS_Service 배포 후 describe에 필드가 보이면 FLS 부여 성공 =="
# 배포 전 describe엔 FLS 미부여로 안 보이던 필드가, PS_Service 배포 후 보이면 FLS가 붙은 것.
sf sobject describe -s WorkOrder -o $ORG --json > /tmp/wo_after.json
sf sobject describe -s WorkOrderLineItem -o $ORG --json > /tmp/woli_after.json
python3 - <<'EOF'
import json
wo={f['name'] for f in json.load(open('/tmp/wo_after.json'))['result']['fields']}
woli={f['name'] for f in json.load(open('/tmp/woli_after.json'))['result']['fields']}
checks=[('WorkOrder',wo,['Repair_Result__c','Action_Taken__c','Root_Cause_Draft__c','Customer_Notification_Draft__c']),
        ('WorkOrderLineItem',woli,['Corrective_Action__c','Verified_By__c','Verified_Date__c','Punch_Status__c'])]
ok=True
for obj,present,names in checks:
    for n in names:
        vis=n in present
        ok=ok and vis
        print(('✅' if vis else '❌'), f'{obj}.{n}', '(describe 노출 → FLS 실효)' if vis else '(여전히 안 보임 → FLS 미부여)')
print('\n== FLS 실효 종합:', '성공' if ok else '실패')
EOF
echo "== 5. FlexiPage 활성화 확인 =="
sf data query -o $ORG --use-tooling-api -q "SELECT DeveloperName FROM FlexiPage WHERE DeveloperName='WorkOrderLineItem_Record_Page'"
