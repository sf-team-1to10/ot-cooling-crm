/**
 * S-07 Slack 전문가 소집 — FSL 스킬 데이터 시딩.
 * T5_Case_Expert_Finder_Swarm Flow가 참조하는 Skill / ServiceResourceSkill을 만든다.
 * 시나리오상 CDU 계열(A-07) 소집 대상은 오도면(설계)·강시공(시공).
 *
 * 재현: sf apex run --file scripts/seed_s07_swarm_skills.apex -o T0INT
 */

// 1) Skill "CDU계열" 조회 (Skill은 setup 객체라 DML 불가 → skills/ 메타데이터로 선배포)
Id cduSkillId = [SELECT Id FROM Skill WHERE MasterLabel = 'CDU계열' LIMIT 1].Id;

// 2) 오도면 ServiceResource 확보(없으면 생성) — 강시공·서정비는 이미 존재
Id odomyeonUserId = [SELECT Id FROM User WHERE Name = '오도면' AND IsActive = true LIMIT 1].Id;
List<ServiceResource> odoSr = [SELECT Id FROM ServiceResource WHERE RelatedRecordId = :odomyeonUserId LIMIT 1];
Id odoSrId;
if (odoSr.isEmpty()) {
    ServiceResource sr = new ServiceResource(
        Name = '오도면', RelatedRecordId = odomyeonUserId, ResourceType = 'T', IsActive = true
    );
    insert sr;
    odoSrId = sr.Id;
} else {
    odoSrId = odoSr[0].Id;
}

Id gangSrId = [SELECT Id FROM ServiceResource WHERE Name = '강시공' LIMIT 1].Id;

// 3) CDU계열 ServiceResourceSkill 부여(오도면·강시공) — 중복 방지
Set<Id> already = new Set<Id>();
for (ServiceResourceSkill srs : [
    SELECT ServiceResourceId FROM ServiceResourceSkill
    WHERE SkillId = :cduSkillId AND ServiceResourceId IN (:odoSrId, :gangSrId)
]) {
    already.add(srs.ServiceResourceId);
}
List<ServiceResourceSkill> toAdd = new List<ServiceResourceSkill>();
for (Id srId : new List<Id>{ odoSrId, gangSrId }) {
    if (!already.contains(srId)) {
        toAdd.add(new ServiceResourceSkill(
            ServiceResourceId = srId,
            SkillId = cduSkillId,
            EffectiveStartDate = Date.newInstance(2022, 1, 1)
        ));
    }
}
if (!toAdd.isEmpty()) {
    insert toAdd;
}

System.debug('SEEDED CDU계열 skill + ServiceResourceSkill 오도면·강시공 (신규 ' + toAdd.size() + '건)');
