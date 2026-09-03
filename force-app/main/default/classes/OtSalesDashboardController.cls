public with sharing class OtSalesDashboardController {

    /* ── Quarter boundaries (reused by several methods) ────────────── */
    private static Date quarterStart() {
        Integer currentMonth = Date.today().month();
        Integer qStartMonth = ((Integer) Math.floor((currentMonth - 1) / 3)) * 3 + 1;
        return Date.newInstance(Date.today().year(), qStartMonth, 1);
    }
    private static Date quarterEnd() {
        return quarterStart().addMonths(3).addDays(-1);
    }

    /* ── Korean month labels ───────────────────────────────────────── */
    private static final List<String> MONTH_LABELS = new List<String>{
        '1월','2월','3월','4월','5월','6월',
        '7월','8월','9월','10월','11월','12월'
    };

    /* ================================================================
       getQuarterlyPerformance
       ================================================================ */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getQuarterlyPerformance() {
        Id userId = UserInfo.getUserId();
        Date qStart = quarterStart();
        Date qEnd   = quarterEnd();
        Decimal goal = 600000000;

        // Closed-Won this quarter
        Decimal closed = 0;
        for (AggregateResult ar : [
            SELECT SUM(Amount) total FROM Opportunity
            WHERE OwnerId = :userId AND CloseDate >= :qStart AND CloseDate <= :qEnd AND IsWon = true
        ]) { if (ar.get('total') != null) closed = (Decimal) ar.get('total'); }

        // Open high-probability (>= 70 %)
        Decimal openHighProb = 0;
        for (AggregateResult ar : [
            SELECT SUM(Amount) total FROM Opportunity
            WHERE OwnerId = :userId AND CloseDate >= :qStart AND CloseDate <= :qEnd
              AND IsClosed = false AND Probability >= 70
        ]) { if (ar.get('total') != null) openHighProb = (Decimal) ar.get('total'); }

        Integer achievementPct = goal == 0 ? 0 : (Integer) Math.round(closed / goal * 100);
        Integer progressPct    = goal == 0 ? 0 : (Integer) Math.round((closed + openHighProb) / goal * 100);
        Integer daysRemaining  = Date.today().daysBetween(qEnd);

        // Monthly data — 3 months in current quarter
        Decimal projected = (closed + openHighProb) / 3;
        List<Map<String, Object>> monthlyData = new List<Map<String, Object>>();

        for (Integer i = 0; i < 3; i++) {
            Date mStart = qStart.addMonths(i);
            Date mEnd   = mStart.addMonths(1).addDays(-1);
            Integer mNum = mStart.month(); // 1-based

            Decimal actual = 0;
            // Only query actuals for past or current months
            if (mStart <= Date.today()) {
                for (AggregateResult ar : [
                    SELECT SUM(Amount) total FROM Opportunity
                    WHERE OwnerId = :userId AND CloseDate >= :mStart AND CloseDate <= :mEnd AND IsWon = true
                ]) { if (ar.get('total') != null) actual = (Decimal) ar.get('total'); }
            }

            monthlyData.add(new Map<String, Object>{
                'label'     => MONTH_LABELS[mNum - 1],
                'actual'    => actual,
                'projected' => projected
            });
        }

        return new Map<String, Object>{
            'closed'         => closed,
            'openHighProb'   => openHighProb,
            'goal'           => goal,
            'achievementPct' => achievementPct,
            'progressPct'    => progressPct,
            'daysRemaining'  => daysRemaining,
            'monthlyData'    => monthlyData
        };
    }

    /* ================================================================
       getPipeline — returns Map<String, Object>
       Stage key  -> Map { 'amount': Decimal, 'pct': Integer }
       'total'    -> Decimal (grand total)
       '_stages'  -> List<String> ordered stage names
       ================================================================ */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPipeline() {
        Id userId = UserInfo.getUserId();
        Date qStart = quarterStart();
        Date qEnd   = quarterEnd();

        // Open pipeline by stage
        Map<String, Decimal> stageAmounts = new Map<String, Decimal>();
        List<String> stageOrder = new List<String>();

        for (AggregateResult ar : [
            SELECT StageName stage, SUM(Amount) total FROM Opportunity
            WHERE OwnerId = :userId AND IsClosed = false
            GROUP BY StageName ORDER BY SUM(Amount) DESC
        ]) {
            String stage = (String) ar.get('stage');
            Decimal amt  = ar.get('total') != null ? (Decimal) ar.get('total') : 0;
            stageAmounts.put(stage, amt);
            stageOrder.add(stage);
        }

        // Closed Won this quarter
        Decimal closedWon = 0;
        for (AggregateResult ar : [
            SELECT SUM(Amount) total FROM Opportunity
            WHERE OwnerId = :userId AND CloseDate >= :qStart AND CloseDate <= :qEnd AND IsWon = true
        ]) { if (ar.get('total') != null) closedWon = (Decimal) ar.get('total'); }

        if (closedWon > 0) {
            stageAmounts.put('Closed Won', closedWon);
            stageOrder.add('Closed Won');
        }

        // Grand total
        Decimal grandTotal = 0;
        for (Decimal v : stageAmounts.values()) { grandTotal += v; }

        // Build result
        Map<String, Object> result = new Map<String, Object>();
        for (String stage : stageOrder) {
            Decimal amt = stageAmounts.get(stage);
            Integer pct = grandTotal == 0 ? 0 : (Integer) Math.round(amt / grandTotal * 100);
            result.put(stage, new Map<String, Object>{ 'amount' => amt, 'pct' => pct });
        }
        result.put('total', grandTotal);
        result.put('_stages', stageOrder);

        return result;
    }

    /* ================================================================
       getKeyDeals — top-5 open opps with probability
       ================================================================ */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getKeyDeals() {
        List<Map<String, Object>> deals = new List<Map<String, Object>>();
        for (Opportunity o : [
            SELECT Id, Name, Amount, StageName, CloseDate, Probability
            FROM Opportunity WHERE OwnerId = :UserInfo.getUserId() AND IsClosed = false
            ORDER BY Amount DESC NULLS LAST LIMIT 5
        ]) {
            deals.add(new Map<String, Object>{
                'id'          => o.Id,
                'name'        => o.Name,
                'amount'      => o.Amount,
                'stage'       => o.StageName,
                'closeDate'   => o.CloseDate != null ? String.valueOf(o.CloseDate) : null,
                'probability' => o.Probability != null ? (Integer) o.Probability : 0
            });
        }
        return deals;
    }

    /* ================================================================
       getContracts — active service contracts (unchanged)
       ================================================================ */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getContracts() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (ServiceContract sc : [
            SELECT Id, Name, Account.Name, EndDate, Status
            FROM ServiceContract WHERE OwnerId = :UserInfo.getUserId() AND Status = 'Active'
            ORDER BY EndDate ASC LIMIT 10
        ]) {
            result.add(new Map<String, Object>{
                'id' => sc.Id, 'name' => sc.Name,
                'account' => sc.Account != null ? sc.Account.Name : '—',
                'endDate' => sc.EndDate != null ? String.valueOf(sc.EndDate) : null,
                'status' => sc.Status
            });
        }
        return result;
    }

    /* ================================================================
       getRecentRecords — recently viewed opps + contracts (unchanged)
       ================================================================ */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRecentRecords() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Opportunity o : [
            SELECT Id, Name FROM Opportunity
            WHERE OwnerId = :UserInfo.getUserId()
            ORDER BY LastViewedDate DESC NULLS LAST LIMIT 3
        ]) {
            result.add(new Map<String, Object>{
                'id' => o.Id, 'name' => o.Name, 'icon' => 'standard:opportunity', 'objType' => 'Opportunity'
            });
        }
        for (ServiceContract sc : [
            SELECT Id, Name FROM ServiceContract
            WHERE OwnerId = :UserInfo.getUserId()
            ORDER BY LastViewedDate DESC NULLS LAST LIMIT 2
        ]) {
            result.add(new Map<String, Object>{
                'id' => sc.Id, 'name' => sc.Name, 'icon' => 'standard:service_contract', 'objType' => 'ServiceContract'
            });
        }
        return result;
    }

    /* ================================================================
       getDashboardData — placeholder for composite fetch
       ================================================================ */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboardData() {
        return new Map<String, Object>();
    }
}
