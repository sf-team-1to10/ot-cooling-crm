import { LightningElement } from "lwc";

const RCA_QUEUE = [
    { id: "q1", caseId: "SF-CASE-20260825-8834", date: "08/25 09:09", asset: "CDU-A-07", status: "RCA 대기", priority: "높음", priCls: "pri pri-high" },
    { id: "q2", caseId: "SF-CASE-20260824-7721", date: "08/24 14:32", asset: "CDU-A-04", status: "RCA 대기", priority: "높음", priCls: "pri pri-high" },
    { id: "q3", caseId: "SF-CASE-20260823-6615", date: "08/23 11:18", asset: "CDU-A-02", status: "RCA 대기", priority: "보통", priCls: "pri pri-med" },
    { id: "q4", caseId: "SF-CASE-20260821-5532", date: "08/21 16:50", asset: "CDU-A-06", status: "정보 수집", priority: "낮음", priCls: "pri pri-low" },
    { id: "q5", caseId: "SF-CASE-20260820-4420", date: "08/20 10:41", asset: "CDU-A-08", status: "정보 수집", priority: "낮음", priCls: "pri pri-low" }
];

const SLA_POINTS = [
    { id: "s1", cx: "10", cy: "83" },
    { id: "s2", cx: "60", cy: "65" },
    { id: "s3", cx: "110", cy: "51" },
    { id: "s4", cx: "160", cy: "45" },
    { id: "s5", cx: "210", cy: "45" },
    { id: "s6", cx: "290", cy: "28" }
];

const MTTR_POINTS = [
    { id: "m1", cx: "10", cy: "38" },
    { id: "m2", cx: "60", cy: "16" },
    { id: "m3", cx: "110", cy: "48" },
    { id: "m4", cx: "160", cy: "56" },
    { id: "m5", cx: "210", cy: "54" },
    { id: "m6", cx: "290", cy: "68" }
];

const RCA_STAGES = [
    { id: "r1", label: "식별", sub: "(Identified)", count: 12 },
    { id: "r2", label: "원인 분석", sub: "(Analysis)", count: 8 },
    { id: "r3", label: "조치 계획", sub: "(Action Plan)", count: 6 },
    { id: "r4", label: "조치 실행", sub: "(Implementation)", count: 4 },
    { id: "r5", label: "검증", sub: "(Verification)", count: 4 },
    { id: "r6", label: "종료", sub: "(Closed)", count: 18 }
];

const TOP_CAUSES = [
    { id: "c1", name: "유량 저하 / 불균형", count: 16, pct: "30.8%", dotStyle: "background:#3B82F6;" },
    { id: "c2", name: "센서 이상 / 오작동", count: 12, pct: "23.1%", dotStyle: "background:#6366F1;" },
    { id: "c3", name: "필터 막힘", count: 9, pct: "17.3%", dotStyle: "background:#F59E0B;" },
    { id: "c4", name: "밸브 / 제어 이상", count: 8, pct: "15.4%", dotStyle: "background:#EF4444;" },
    { id: "c5", name: "기타", count: 7, pct: "13.4%", dotStyle: "background:#94A3B8;" }
];

const RECENT_RCA = [
    { id: "rc1", caseId: "SF-CASE-20260818-3312", asset: "CDU-A-03", completed: "08/20 14:22", rootCause: "필터 막힘으로 인한 유량 저하", action: "필터 교체 및 차압 알림 임계값 최적화", status: "완료", statusCls: "badge badge-done" },
    { id: "rc2", caseId: "SF-CASE-20260816-2211", asset: "CDU-A-01", completed: "08/18 16:05", rootCause: "센서 드리프트로 인한 오감보", action: "센서 교정 및 펌웨어 업데이트", status: "완료", statusCls: "badge badge-done" },
    { id: "rc3", caseId: "SF-CASE-20260815-1105", asset: "CDU-A-05", completed: "08/17 11:33", rootCause: "제어 밸브 응답 지연", action: "밸브 액추에이터 점검 및 교체", status: "완료", statusCls: "badge badge-done" }
];

export default class OtCoolingRca extends LightningElement {
    get rcaQueue() {
        return RCA_QUEUE;
    }

    get slaPoints() {
        return SLA_POINTS;
    }

    get mttrPoints() {
        return MTTR_POINTS;
    }

    get rcaStages() {
        return RCA_STAGES;
    }

    get topCauses() {
        return TOP_CAUSES;
    }

    get recentRca() {
        return RECENT_RCA;
    }
}
