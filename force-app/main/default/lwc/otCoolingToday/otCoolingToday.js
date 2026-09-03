import { LightningElement } from "lwc";
import COOLINX_HALL from "@salesforce/resourceUrl/coolinxHall";

const ALERTS = [
    {
        id: "a1",
        time: "09:09",
        ago: "5분 전",
        asset: "CDU-A-07",
        desc: "2차 차압 상승",
        value: "0.31 bar",
        valClass: "val-danger",
        threshold: "기준 0.30 bar",
        status: "주의",
        badgeCls: "badge badge-warn"
    },
    {
        id: "a2",
        time: "08:56",
        ago: "18분 전",
        asset: "CDU-A-04",
        desc: "유량 저하",
        value: "1,380 LPM",
        valClass: "val-info",
        threshold: "기준 1,500 LPM",
        status: "정상복귀",
        badgeCls: "badge badge-ok"
    },
    {
        id: "a3",
        time: "08:50",
        ago: "24분 전",
        asset: "Hall A",
        desc: "PUE",
        value: "1.14",
        valClass: "val-normal",
        threshold: "목표 1.15",
        status: "정보",
        badgeCls: "badge badge-info"
    }
];

const HALL_ASSETS = [
    { id: "h1", name: "CDU-A-01", status: "Normal", top: 25, left: 15, ok: true },
    { id: "h2", name: "CDU-A-02", status: "Normal", top: 25, left: 30, ok: true },
    { id: "h3", name: "CDU-A-03", status: "Normal", top: 25, left: 45, ok: true },
    { id: "h4", name: "CDU-A-04", status: "Normal", top: 25, left: 60, ok: true },
    { id: "h5", name: "CDU-A-05", status: "Normal", top: 40, left: 75, ok: true },
    { id: "h6", name: "CDU-A-06", status: "Normal", top: 65, left: 15, ok: true },
    { id: "h7", name: "CDU-A-07", status: "Watch", top: 65, left: 38, ok: false },
    { id: "h8", name: "CDU-A-08", status: "Normal", top: 65, left: 60, ok: true }
];

const DISPATCHES = [
    {
        id: "d1",
        name: "김기술",
        caseId: "SF-CASE-20260825-8834",
        asset: "CDU-A-07",
        type: "이상 대응",
        status: "현장 출동중",
        statusCls: "badge badge-dispatch",
        eta: "25분",
        location: "5.2 km · 강남구 테헤란로 123",
        avatarStyle: "background: #6366F1;"
    },
    {
        id: "d2",
        name: "박현장",
        caseId: "SF-CASE-20260825-8831",
        asset: "CDU-A-08",
        type: "예방점검",
        status: "현장 대기",
        statusCls: "badge badge-waiting",
        eta: "10분",
        location: "현장 대기 중 · Hall A",
        avatarStyle: "background: #F59E0B;"
    },
    {
        id: "d3",
        name: "이장비",
        caseId: "SF-CASE-20260825-8829",
        asset: "CDU-A-03",
        type: "이상 대응",
        status: "작업 완료",
        statusCls: "badge badge-done",
        eta: "—",
        location: "작업 완료 · 09:02",
        avatarStyle: "background: #10B981;"
    }
];

export default class OtCoolingToday extends LightningElement {
    hallImageUrl = COOLINX_HALL;

    get alerts() {
        return ALERTS;
    }

    get hallAssets() {
        return HALL_ASSETS.map((h) => ({
            ...h,
            cls: h.ok ? "ha-item ha-normal" : "ha-item ha-watch",
            badgeCls: h.ok ? "ha-badge ha-badge-normal" : "ha-badge ha-badge-watch",
            style: `top:${h.top}%;left:${h.left}%;`
        }));
    }

    get dispatches() {
        return DISPATCHES;
    }
}
