#!/usr/bin/env python3
"""T4-07 QA 시딩 — CDU-A-07 유량 기준선(D6 3,180) + 예방정비 12회차 시계열.
사용:  python3 scripts/seed_t4_07.py check   # org 현황만 출력 (아무것도 안 만듦)
       python3 scripts/seed_t4_07.py seed    # 시운전 WO 1 + 예방정비 WO 12 생성·측정값 입력
       python3 scripts/seed_t4_07.py verify  # 결과 쿼리 (Drift·Delta·Trend_Flag·WO Risk)
백로그 데이터시딩_값 47~59행. 시간순 insert → CreatedDate 정렬이 시계열."""
import json, subprocess, sys, time

ORG = "T4OPS"
ASSET_LIKE = "%CDU-A-07%"
ROUNDS = [3172, 3181, 3165, 3170, 3142, 3150, 3120, 3098, 3061, 3015, 2992, 2970]

def sf(*args):
    r = subprocess.run(["sf", *args, "--json"], capture_output=True, text=True)
    try:
        out = json.loads(r.stdout)
    except json.JSONDecodeError:
        print(r.stdout, r.stderr); sys.exit(1)
    if out.get("status") != 0:
        print("ERROR:", json.dumps(out.get("message") or out, ensure_ascii=False)[:800]); sys.exit(1)
    return out["result"]

def q(soql):
    return sf("data", "query", "-q", soql, "-o", ORG)["records"]

def create(sobj, **vals):
    v = " ".join(f"{k}='{val}'" for k, val in vals.items())
    return sf("data", "create", "record", "-s", sobj, "-v", v, "-o", ORG)["id"]

def update(sobj, rid, **vals):
    v = " ".join(f"{k}='{val}'" for k, val in vals.items())
    sf("data", "update", "record", "-s", sobj, "-i", rid, "-v", v, "-o", ORG)

def asset():
    a = q(f"SELECT Id, Name FROM Asset WHERE Name LIKE '{ASSET_LIKE}' LIMIT 1")
    if not a: print("Asset CDU-A-07 없음 — T0-05 선행 필요"); sys.exit(1)
    return a[0]

def check():
    a = asset(); print("Asset:", a["Name"], a["Id"])
    pb = q("SELECT Id, Name, IsActive FROM Pricebook2 WHERE IsStandard = true")
    print("Standard Pricebook:", pb)
    wos = q(f"SELECT Id, Subject, Work_Subtype__c, CreatedDate FROM WorkOrder WHERE AssetId='{a['Id']}' ORDER BY CreatedDate")
    print(f"WorkOrder {len(wos)}건"); [print("  ", w["Work_Subtype__c"], w["Subject"], w["CreatedDate"][:16]) for w in wos]
    verify()

def flow_line(wo_id):
    for _ in range(5):
        l = q(f"SELECT Id FROM WorkOrderLineItem WHERE WorkOrderId='{wo_id}' AND Measurement_Item_Code__c='유량' LIMIT 1")
        if l: return l[0]["Id"]
        time.sleep(1)
    print("자동생성 유량 라인 없음 — T4-03 Flow 활성 상태 확인"); sys.exit(1)

def seed():
    a = asset(); aid = a["Id"]
    pb = q("SELECT Id FROM Pricebook2 WHERE IsStandard = true")[0]["Id"]
    # 1) D6 시운전 — 재시험 통과값 3,180 = 기준선 (1회차 2,850 불합격은 생략)
    wo = create("WorkOrder", AssetId=aid, Pricebook2Id=pb, Work_Subtype__c="시운전", Subject="[시딩] D6 시운전 CDU-A-07")
    li = flow_line(wo)
    update("WorkOrderLineItem", li, AssetId=aid, Line_Item_Role__c="시험", Measured_Value__c=3180, Judgement__c="합격")
    print("시운전 WO", wo, "유량 3180 합격(기준선)")
    time.sleep(1)
    # 2) 예방정비 12회차
    for i, v in enumerate(ROUNDS, 1):
        wo = create("WorkOrder", AssetId=aid, Pricebook2Id=pb, Work_Subtype__c="예방정비", Subject=f"[시딩] 예방정비 {i:02d}회차 CDU-A-07")
        li = flow_line(wo)
        update("WorkOrderLineItem", li, AssetId=aid, Measured_Value__c=v, Judgement__c="합격")
        print(f"{i:02d}회차 WO {wo} 유량 {v}")
        time.sleep(1)
    verify()

def verify():
    a = asset()
    rows = q(f"SELECT WorkOrder.Subject, WorkOrder.Risk_Level__c, Measured_Value__c, Baseline_Value__c, Drift_From_Baseline__c, Delta_From_Previous__c, Trend_Flag__c, Judgement__c, CreatedDate FROM WorkOrderLineItem WHERE AssetId='{a['Id']}' AND Measurement_Item_Code__c='유량' ORDER BY CreatedDate")
    print(f"\n유량 WOLI {len(rows)}건 (CreatedDate 순)")
    print(f"{'Subject':34} {'측정':>6} {'기준':>6} {'Drift%':>7} {'Delta':>7} {'Trend':>4} {'Judge':>4} {'WO Risk':>7}")
    for r in rows:
        d = r.get("Drift_From_Baseline__c"); dl = r.get("Delta_From_Previous__c")
        print(f"{(r['WorkOrder'] or {}).get('Subject') or '':34} {r.get('Measured_Value__c') or '':>6} {r.get('Baseline_Value__c') or '':>6} {('' if d is None else f'{d:.1f}'):>7} {('' if dl is None else f'{dl:.0f}'):>7} {r.get('Trend_Flag__c') or '':>4} {r.get('Judgement__c') or '':>4} {(r['WorkOrder'] or {}).get('Risk_Level__c') or '':>7}")
    print("\n기대: 1~8회차 정상 / 9회차 주의(규칙② 7·8·9 3연속 하락, Drift -3.7) / 10회차 주의(규칙① -5.2 경계 + 규칙②) / 11·12회차 주의 / WO Risk 보통 (이상·높음은 규칙③ 보류로 미구현)")

cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
{"check": check, "seed": seed, "verify": verify}[cmd]()
