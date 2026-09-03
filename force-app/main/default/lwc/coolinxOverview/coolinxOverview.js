import { LightningElement, track } from "lwc";
import COOLINX_HALL from "@salesforce/resourceUrl/coolinxHall";

/**
 * Coolinx Overview — coolinx_overview_prototype.html을 Experience Cloud LWC로
 * 그대로 옮긴 데모 대시보드. KPI 수치·도넛/라인/막대 차트·헬스바·알람 표는
 * 프로토타입과 동일하게 전부 하드코딩(정적)이다.
 *
 * 중앙 "데이터센터 개요"는 coolinxHall 정적 리소스(아이소메트릭 냉각설비
 * 조감도)를 배경으로 깔고, 그 위에 인터랙티브 HUD 레이어를 얹어 실시간
 * 모니터링 뷰처럼 연출한다:
 *   - 배경: 느린 Ken Burns 드리프트 + 마우스 패럴랙스 틸트
 *   - 오버레이: 라이브 배지·타임스탬프·스캔 스윕·냉수 흐름 입자·열점
 *   - 장비 마커: hover/클릭 시 정보 카드, 선택 시 나머지 디밍
 *   - 새로고침: 온도 미세 변동 + 스윕 1회 재생
 * 마커 좌표/수치는 데모용 하드코딩이며 재조회할 실제 데이터는 없다.
 *
 * 사이드바 내비게이션만 실제 상호작용을 위해 for:each + active 토글로 구현했고,
 * 나머지는 마크업 그대로다.
 */
const NAV_ITEMS = [
    { id: "overview", label: "개요", icon: "⌂", chev: false },
    { id: "equipment", label: "장비", icon: "▣", chev: true },
    { id: "alarms", label: "알람", icon: "♧", chev: false },
    { id: "analytics", label: "분석", icon: "⌁", chev: false },
    { id: "reports", label: "리포트", icon: "▤", chev: false },
    { id: "maintenance", label: "정비", icon: "⚒", chev: false },
    { id: "settings", label: "설정", icon: "⚙", chev: false }
];

// 중앙 조감도 위에 얹는 라이브 마커 (데모 — 좌표 %/상태/기준값 하드코딩)
const HALL_MARKERS = [
    { id: "cdu-a-01", label: "CDU-A-01", top: 34, left: 19, status: "ok", base: 18.6, flow: 2010, load: 71 },
    { id: "cdu-a-03", label: "CDU-A-03", top: 28, left: 39, status: "ok", base: 18.3, flow: 1985, load: 68 },
    { id: "cdu-a-05", label: "CDU-A-05", top: 23, left: 60, status: "warn", base: 19.1, flow: 1902, load: 84 },
    { id: "crah-a-04", label: "CRAH-A-04", top: 40, left: 80, status: "ok", base: 18.0, flow: 2044, load: 63 },
    {
        id: "cdu-a-07",
        label: "CDU-A-07",
        top: 62,
        left: 29,
        status: "crit",
        base: 24.2,
        flow: 1961,
        load: 92,
        alert: "냉수 유량 이상"
    },
    { id: "crah-a-02", label: "CRAH-A-02", top: 65, left: 57, status: "ok", base: 18.4, flow: 1998, load: 66 }
];

const STATUS_CLASS = { ok: "hall-mk ok", warn: "hall-mk warn", crit: "hall-mk crit" };
const STATUS_LABEL = { ok: "정상", warn: "주의", crit: "이상" };

export default class CoolinxOverview extends LightningElement {
    // 중앙 조감도 이미지 (정적 리소스 URL)
    hallImageUrl = COOLINX_HALL;

    @track activeNav = "overview";
    @track lastUpdate = nowLabel();
    @track markers = HALL_MARKERS.map((m) => ({ ...m, temp: m.base }));

    _hoveredId = null;
    _selectedId = null;
    _tilt = "";
    _refreshing = false;
    _raf = null;
    _clockTimer = null;

    connectedCallback() {
        // 타임스탬프만 흐르게 해서 "실시간" 감을 준다 (데이터 자체는 정적).
        this._clockTimer = setInterval(() => {
            this.lastUpdate = nowLabel();
        }, 5000);
    }

    disconnectedCallback() {
        clearInterval(this._clockTimer);
        if (this._raf) {
            cancelAnimationFrame(this._raf);
        }
    }

    get navItems() {
        return NAV_ITEMS.map((item) => ({
            ...item,
            cls: item.id === this.activeNav ? "nav-link active" : "nav-link"
        }));
    }

    get activeId() {
        return this._hoveredId || this._selectedId;
    }

    get hallImageClass() {
        let cls = "hall-image";
        if (this._refreshing) {
            cls += " refreshing";
        }
        if (this.activeId) {
            cls += " has-active";
        }
        return cls;
    }

    get sceneStyle() {
        return this._tilt;
    }

    get hallMarkers() {
        const active = this.activeId;
        return this.markers.map((m) => ({
            ...m,
            cls: (STATUS_CLASS[m.status] || "hall-mk ok") + (m.id === active ? " active" : ""),
            style: `top:${m.top}%;left:${m.left}%;`,
            tempLabel: `${m.temp.toFixed(1)}°C`,
            flowLabel: `${m.flow.toLocaleString()} L/min`,
            loadLabel: `${m.load}%`,
            statusLabel: STATUS_LABEL[m.status] || "정상",
            ariaLabel: `${m.label} ${STATUS_LABEL[m.status] || "정상"}, ${m.temp.toFixed(1)}도`
        }));
    }

    get activeMarker() {
        const id = this.activeId;
        if (!id) {
            return null;
        }
        const m = this.hallMarkers.find((x) => x.id === id);
        if (!m) {
            return null;
        }
        const hx = m.left < 38 ? "0" : m.left > 62 ? "-100%" : "-50%";
        const vy = m.top < 34 ? "10px" : "calc(-100% - 10px)";
        return {
            ...m,
            tipDotCls: `tip-dot ${m.status}`,
            tipStyle: `top:${m.top}%;left:${m.left}%;transform:translate(${hx},${vy});`
        };
    }

    handleNav(event) {
        event.preventDefault();
        this.activeNav = event.currentTarget.dataset.id;
    }

    handleMarkerEnter(event) {
        this._hoveredId = event.currentTarget.dataset.id;
    }

    handleMarkerLeave() {
        this._hoveredId = null;
    }

    handleMarkerClick(event) {
        const id = event.currentTarget.dataset.id;
        this._selectedId = this._selectedId === id ? null : id;
    }

    handleMarkerKey(event) {
        if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            this.handleMarkerClick(event);
        }
    }

    handleTipLink(event) {
        // 데모 — 실제 상세 페이지 연결 없음.
        event.preventDefault();
    }

    // 마우스 위치로 배경 레이어를 미세하게 기울여 "라이브 카메라" 느낌.
    handleStageMove(event) {
        const stage = this.template.querySelector(".hall-image");
        if (!stage) {
            return;
        }
        const rect = stage.getBoundingClientRect();
        const px = (event.clientX - rect.left) / rect.width - 0.5;
        const py = (event.clientY - rect.top) / rect.height - 0.5;
        if (this._raf) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._raf = requestAnimationFrame(() => {
            this._raf = null;
            const rx = (-py * 3.5).toFixed(2);
            const ry = (px * 5).toFixed(2);
            this._tilt = `transform: perspective(900px) rotateX(${rx}deg) rotateY(${ry}deg) scale(1.015);`;
        });
    }

    handleStageLeave() {
        this._tilt = "";
        this._hoveredId = null;
    }

    // 새로고침 — 마커 온도를 미세하게 흔들고 스캔 스윕을 1회 재생.
    handleRefresh() {
        this.markers = this.markers.map((m) => {
            const jitter = (Math.random() - 0.5) * 0.6;
            return { ...m, temp: Math.round((m.base + jitter) * 10) / 10 };
        });
        this.lastUpdate = nowLabel();
        this._refreshing = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this._refreshing = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this._refreshing = false;
            }, 1000);
        });
    }
}

function nowLabel() {
    const d = new Date();
    const p = (n) => String(n).padStart(2, "0");
    return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
