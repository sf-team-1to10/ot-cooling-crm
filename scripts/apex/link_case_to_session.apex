MessagingSession ms = [SELECT Id, CaseId FROM MessagingSession WHERE Id = '0Mwbm00000I3miTCAR'];
if (ms.CaseId == null) {
    ms.CaseId = '500bm00002siJy6AAE';
    update ms;
    System.debug('linked Case 00001465 to session ' + ms.Id);
} else {
    System.debug('session already has CaseId: ' + ms.CaseId);
}
