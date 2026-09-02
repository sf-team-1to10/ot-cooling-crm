// CDU-A-01~12 중복 Asset 제거 — 참조 전부 재연결 후 삭제

List<Asset> allCDUs = [
    SELECT Id, Name, CreatedDate
    FROM Asset WHERE Name LIKE 'CDU-A-%'
    ORDER BY Name, CreatedDate ASC
];

Map<String, Id> keepMap = new Map<String, Id>();
Set<Id> deleteIds = new Set<Id>();

for (Asset a : allCDUs) {
    if (!keepMap.containsKey(a.Name)) {
        keepMap.put(a.Name, a.Id);
    } else {
        deleteIds.add(a.Id);
    }
}
System.debug('Keep: ' + keepMap.size() + ', Delete: ' + deleteIds.size());

// Case 재연결
List<Case> cases = [SELECT Id, AssetId, Asset.Name FROM Case WHERE AssetId IN :deleteIds];
for (Case c : cases) {
    c.AssetId = keepMap.get(c.Asset.Name);
}
if (!cases.isEmpty()) { update cases; System.debug('Cases relinked: ' + cases.size()); }

// WorkOrder 재연결
List<WorkOrder> wos = [SELECT Id, AssetId, Asset.Name FROM WorkOrder WHERE AssetId IN :deleteIds];
for (WorkOrder wo : wos) {
    wo.AssetId = keepMap.get(wo.Asset.Name);
}
if (!wos.isEmpty()) { update wos; System.debug('WOs relinked: ' + wos.size()); }

// Entitlement 재연결
List<Entitlement> ents = [SELECT Id, AssetId, Asset.Name FROM Entitlement WHERE AssetId IN :deleteIds];
for (Entitlement e : ents) {
    e.AssetId = keepMap.get(e.Asset.Name);
}
if (!ents.isEmpty()) { update ents; System.debug('Entitlements relinked: ' + ents.size()); }

// 삭제
List<Asset> toDelete = [SELECT Id FROM Asset WHERE Id IN :deleteIds];
delete toDelete;
System.debug('Deleted: ' + toDelete.size());
System.debug('=== DEDUP COMPLETE ===');
