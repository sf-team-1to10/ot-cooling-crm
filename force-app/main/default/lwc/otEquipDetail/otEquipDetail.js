import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getEquipmentDetail from '@salesforce/apex/OTEquipDashboardController.getEquipmentDetail';
import setAssetContextFromLwc from '@salesforce/apex/T5SetAssetContextService.setAssetContextFromLwc';
import gallery01 from '@salesforce/resourceUrl/OT_CDU_Gallery_01';
import gallery02 from '@salesforce/resourceUrl/OT_CDU_Gallery_02';
import gallery03 from '@salesforce/resourceUrl/OT_CDU_Gallery_03';
import gallery04 from '@salesforce/resourceUrl/OT_CDU_Gallery_04';
import gallery05 from '@salesforce/resourceUrl/OT_CDU_Gallery_05';

const METRICS = {
    flow: { label:'CHW Flow', unit:'L/min', from:105, to:71, band:[95,115], vmin:60, vmax:125, interp:'냉수 유량은 기준선 하한보다 낮은 상태로 관찰되고 있으며, 상세 이력과 함께 확인이 필요합니다.' },
    dp:   { label:'ΔP (차압)', unit:'kPa', from:122, to:148, band:[110,140], vmin:95, vmax:165, interp:'차압은 완만한 상승세로, 기준선 상단에 근접해 관찰이 필요합니다.' },
    temp: { label:'공급수 온도', unit:'°C', from:17.9, to:18.2, band:[16,19], vmin:14.5, vmax:20.5, interp:'공급수 온도는 기준선 범위 내에서 안정적으로 유지되고 있습니다.' },
    dt:   { label:'ΔT (온도차)', unit:'°C', from:8.0, to:6.1, band:[7,12], vmin:4.5, vmax:13.5, interp:'온도차(ΔT)가 기준선 하한 부근으로 낮아졌습니다. 부하 조건과 함께 검토가 필요합니다.' }
};
const RANGES = {
    '1':['01:59','02:14','02:29','02:44','02:59'],
    '8':['19:00','21:00','23:00','01:00','03:00'],
    '24':['03:00','09:00','15:00','21:00','03:00'],
    '168':['8/24','8/25','8/26','8/27','8/28','8/29','8/30']
};
const TIMELINE = [
    { d:'2026-03-12', cat:'정기점검', desc:'정기 점검 결과 정상. 다음 점검일 2026-06-12.', att:1 },
    { d:'2025-10-15', cat:'예방정비', desc:'연결부 체결 상태 및 필터 상태 확인.', att:1 },
    { d:'2024-10-15', cat:'서비스 작업', desc:'현장 점검 및 운전 상태 확인.', att:1 },
    { d:'2022-06-18', cat:'설치/시운전/인수', desc:'설치 및 인수 완료. 서비스 계약 및 보증 적용 시작.', att:2 },
    { d:'2022-05-30', cat:'변경관리', desc:'Rev.B 변경 적용 — F-07 변경 구간 반영.', att:1 },
    { d:'2022-05-22', cat:'시운전', desc:'시운전 재시험 합격 — 체결 상태 조정 후 재시험 완료.', att:1 }
];
const DOCS = [
    { group:'장비 매뉴얼', items:[{ name:'CF-CDU-L2L-1350-G1 운전·유지보수 매뉴얼', meta:'Rev.3 · 2024-01-18 · PDF' }] },
    { group:'설치 및 인수 문서', items:[{ name:'설치 완료 확인서 · 인수 체크리스트', meta:'2022-06-18 · PDF' }] },
    { group:'점검 보고서', items:[{ name:'정기 점검 보고서', meta:'2026-03-12 · PDF' },{ name:'정기 점검 보고서', meta:'2025-12-10 · PDF' }] },
    { group:'변경 도면 및 Revision', items:[{ name:'배관 계통도 Rev.B (F-07 구간 반영)', meta:'2022-05-30 · DWG/PDF' }] },
    { group:'서비스 보고서', items:[{ name:'현장 서비스 작업 보고서', meta:'2024-10-15 · PDF' }] }
];
const CHAT_ANALYSIS = '냉수 유량이 기준선보다 낮은 상태로 관찰되고 있습니다. 확인이 필요한 부분: 2차측 스트레이너 차압·바이패스 밸브 저항, 배관 연결부 체결 상태, 순환 펌프·제어·유량계 센서. 근본 원인은 현장 확인 후 판단합니다.';

export default class OtEquipDetail extends NavigationMixin(LightningElement) {
    @api assetId;
    @track activeTab = 'overview';
    @track curMetric = 'flow';
    @track curRange = '8';
    @track drawerOpen = false;
    @track drawerMinimized = false;
    @track lightboxOpen = false;
    @track galIdx = 0;
    @track chatMessages = [];
    @track chatInput = '';

    // T5-07 — 2026-08-31: OTEquipDashboardController.getEquipmentDetail()에
    // 연결(사용자 요청 — 이 컴포넌트가 Apex를 전혀 호출 안 하고 있던 걸
    // 발견, T5_서비스에이전트_작업기록.md 참고). 자산 핵심 필드(이름·위치·
    // 상태·보증·미조치건수)와 게이지 스냅샷(gaugesJson)은 실데이터로
    // 교체됨. 다중 지표(ΔP/온도 등)·1h~7일 범위별 시계열 추세 그래프는
    // Apex에 그 데이터 모델이 아직 없어 이번 범위에서는 손대지 않고
    // METRICS/RANGES 시뮬레이션을 유지 — 후속 작업으로 트래커에 기록.
    @track detail = null;
    @track gauges = [];

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        if (ref && ref.state && ref.state.assetId) {
            this.assetId = ref.state.assetId;
        }
    }

    @wire(getEquipmentDetail, { assetId: '$assetId' })
    wiredDetail({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('장비 상세 로드 실패', error);
            return;
        }
        if (!data) return;
        this.detail = data;
        this.gauges = this.parseGauges(data.gaugesJson);
    }

    parseGauges(gaugesJson) {
        if (!gaugesJson) return [];
        try {
            return JSON.parse(gaugesJson) || [];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('gaugesJson 파싱 실패', e);
            return [];
        }
    }

    get primaryGauge() {
        if (!this.gauges || this.gauges.length === 0) return null;
        return this.gauges.find(g => /flow/i.test(g.measurementItemCode || '')) || this.gauges[0];
    }

    get assetName() { return this.detail ? this.detail.name : ''; }
    get assetMeta() {
        if (!this.detail) return '';
        const d = this.detail;
        const parts = [d.assetType, d.family, d.location, d.serialNumber ? `Serial No. ${d.serialNumber}` : null,
            d.installDate ? `설치일 ${d.installDate}` : null];
        return parts.filter(Boolean).join(' · ');
    }

    // Tabs
    get tabs() {
        const t = [
            { key:'overview', label:'상태 개요' },
            { key:'trend', label:'추세 분석' },
            { key:'service', label:'서비스·보증' },
            { key:'history', label:'이력·문서' }
        ];
        return t.map(x => ({ ...x, cls: x.key === this.activeTab ? 'tab on' : 'tab' }));
    }
    get isOverview() { return this.activeTab === 'overview'; }
    get isTrend() { return this.activeTab === 'trend'; }
    get isService() { return this.activeTab === 'service'; }
    get isHistory() { return this.activeTab === 'history'; }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        if (this.isTrend) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.renderTrendChart(), 50);
        }
    }

    // Gallery
    get galleryImages() {
        return [
            { url: gallery01, cap:'3/4 스튜디오 뷰', badge:'대표 이미지' },
            { url: gallery02, cap:'정면 뷰', badge:'' },
            { url: gallery03, cap:'점검부 개방 · 내부 배관', badge:'' },
            { url: gallery04, cap:'후면 배관 인터페이스', badge:'' },
            { url: gallery05, cap:'설치 현장', badge:'' }
        ];
    }
    get currentImage() { return this.galleryImages[this.galIdx]; }
    get galCounter() { return `${this.galIdx + 1} / ${this.galleryImages.length}`; }
    get hasBadge() { return !!this.currentImage.badge; }
    get thumbItems() {
        return this.galleryImages.map((g, i) => ({
            ...g, idx: i, cls: i === this.galIdx ? 'thumb on' : 'thumb'
        }));
    }
    handleGalPrev() { this.galIdx = (this.galIdx - 1 + this.galleryImages.length) % this.galleryImages.length; }
    handleGalNext() { this.galIdx = (this.galIdx + 1) % this.galleryImages.length; }
    handleThumb(event) { this.galIdx = parseInt(event.currentTarget.dataset.idx, 10); }
    handleZoom() { this.lightboxOpen = true; }
    handleLightboxClose() { this.lightboxOpen = false; }

    // Condition rows — 실데이터(자산 상태·게이지) + 아직 백엔드 데이터
    // 모델이 없는 항목("운전 상태"·"Advisory 지속")은 정직하게 "—"로 표시.
    get conditionRows() {
        const d = this.detail;
        const g = this.primaryGauge;
        const isAdv = d && d.stateCode === 'adv';
        return [
            { label:'자산 상태', value: d ? d.stateLabel : '—', cls: isAdv ? 'val amber' : 'val teal' },
            { label:'관찰 항목', value: g ? g.measurementItemCode : '이상 감지된 항목 없음', cls:'val' },
            { label:'현재값', value: g ? `${g.currentValue}` : '—', cls: isAdv ? 'val amber mono' : 'val mono' },
            { label:'직전 측정값', value: g ? `${g.previousValue}` : '—', cls:'val mono' },
            { label:'보증', value: d ? (d.warrantyType || '정보 없음') : '—', cls:'val' },
            { label:'미조치 건수', value: d && d.openItemsSummary != null ? `${d.openItemsSummary}건` : '0건', cls:'val mono' },
            { label:'다음 정비', value: d && d.nextMaintenance ? d.nextMaintenance : '—', cls:'val mono' }
        ];
    }

    // Trend chart
    get metricButtons() {
        const btns = [
            { key:'flow', label:'CHW Flow' },
            { key:'dp', label:'ΔP' },
            { key:'temp', label:'공급수 온도' },
            { key:'dt', label:'ΔT' }
        ];
        return btns.map(b => ({ ...b, cls: b.key === this.curMetric ? 'seg-btn on' : 'seg-btn' }));
    }
    get rangeButtons() {
        const btns = [
            { key:'1', label:'1시간' },
            { key:'8', label:'8시간' },
            { key:'24', label:'24시간' },
            { key:'168', label:'7일' }
        ];
        return btns.map(b => ({ ...b, cls: b.key === this.curRange ? 'seg-btn on' : 'seg-btn' }));
    }
    get trendInterp() { return METRICS[this.curMetric].interp; }
    get trendLegendText() {
        const M = METRICS[this.curMetric];
        return `${M.label} (${M.unit}) · Operating Baseline (${M.band[0]}–${M.band[1]} ${M.unit})`;
    }

    handleMetric(event) {
        this.curMetric = event.currentTarget.dataset.key;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.renderTrendChart(), 10);
    }
    handleRange(event) {
        this.curRange = event.currentTarget.dataset.key;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.renderTrendChart(), 10);
    }
    handleRefresh() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.renderTrendChart(), 10);
    }

    renderTrendChart() {
        const el = this.template.querySelector('.trend-chart');
        if (!el) return;
        const M = METRICS[this.curMetric];
        const W=760, H=300, pL=46, pR=18, pT=16, pB=34;
        const iw=W-pL-pR, ih=H-pT-pB;
        const n=49;
        const pts = [];
        for (let i=0;i<n;i++) {
            const t=i/(n-1);
            let v=M.from + (M.to-M.from)*Math.pow(t,1.3);
            v += Math.sin(i*1.7)*((Math.abs(M.from-M.to)*0.05)+0.4);
            pts.push(v);
        }
        pts[n-1]=M.to;
        const Y = v => pT + ih - (v-M.vmin)/(M.vmax-M.vmin)*ih;
        const X = i => pL + i/(n-1)*iw;
        let d='', area='';
        for (let i=0;i<n;i++) { d+=(i?'L':'M')+X(i).toFixed(1)+' '+Y(pts[i]).toFixed(1)+' '; }
        area=d+'L'+X(n-1).toFixed(1)+' '+Y(M.vmin).toFixed(1)+' L'+pL+' '+Y(M.vmin).toFixed(1)+' Z';
        let g='';
        const yt=[M.vmin,M.vmin+(M.vmax-M.vmin)*0.25,M.vmin+(M.vmax-M.vmin)*0.5,M.vmin+(M.vmax-M.vmin)*0.75,M.vmax];
        yt.forEach(v => {
            g+=`<line x1="${pL}" y1="${Y(v).toFixed(1)}" x2="${W-pR}" y2="${Y(v).toFixed(1)}" stroke="#e9e9ea"/>`;
            g+=`<text x="${pL-8}" y="${(Y(v)+3).toFixed(1)}" text-anchor="end" font-size="9.5" font-family="JetBrains Mono,monospace" fill="#7f95a9">${(Math.round(v*10)/10)}</text>`;
        });
        const xl=RANGES[this.curRange];
        xl.forEach((lb,q) => {
            const xx=pL+q/(xl.length-1)*iw;
            g+=`<text x="${xx.toFixed(1)}" y="${H-12}" text-anchor="middle" font-size="9.5" font-family="JetBrains Mono,monospace" fill="#7f95a9">${lb}</text>`;
        });
        const bandY1=Y(M.band[1]), bandY0=Y(M.band[0]);
        const last=X(n-1), lastY=Y(pts[n-1]);

        let evtMarkers = '';
        if ((this.curRange === '8' || this.curRange === '1') && this.curMetric === 'flow') {
            const events = [
                { frac: this.curRange === '1' ? 0.66 : 0.905, color: '#f57c00', time: '02:14', label: 'P3 Advisory 발생' },
                { frac: this.curRange === '1' ? 0.92 : 0.955, color: '#5980a6', time: '02:37', label: '고객 알림 확인' }
            ];
            events.forEach(e => {
                const ex = pL + e.frac * iw;
                evtMarkers +=
                    `<line x1="${ex.toFixed(1)}" y1="${pT}" x2="${ex.toFixed(1)}" y2="${(pT+ih)}" stroke="${e.color}" stroke-width="1.4" stroke-dasharray="4 3"/>` +
                    `<circle cx="${ex.toFixed(1)}" cy="${pT}" r="4" fill="${e.color}"/>` +
                    `<text x="${ex.toFixed(1)}" y="${(pT-6)}" text-anchor="middle" font-size="9.5" font-weight="700" fill="${e.color}" font-family="ui-monospace,Consolas,monospace">${e.time}</text>`;
            });
        }

        el.innerHTML=`<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" style="width:100%">`+
            `<rect x="${pL}" y="${bandY1.toFixed(1)}" width="${iw}" height="${(bandY0-bandY1).toFixed(1)}" fill="rgba(76,175,80,.08)"/>`+
            `<line x1="${pL}" y1="${bandY0.toFixed(1)}" x2="${W-pR}" y2="${bandY0.toFixed(1)}" stroke="#4caf50" stroke-dasharray="5 3"/>`+
            `<line x1="${pL}" y1="${bandY1.toFixed(1)}" x2="${W-pR}" y2="${bandY1.toFixed(1)}" stroke="#81c784" stroke-dasharray="4 4"/>`+
            g + evtMarkers +
            `<path d="${area}" fill="rgba(89,128,166,.07)"/>`+
            `<path d="${d}" fill="none" stroke="#5980a6" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`+
            `<circle cx="${last.toFixed(1)}" cy="${lastY.toFixed(1)}" r="4" fill="#16b8c8" stroke="#fff" stroke-width="1.6"/>`+
            `</svg>`;
    }

    // Timeline & Docs
    get timelineItems() { return TIMELINE; }
    get docGroups() { return DOCS; }

    // Events
    get recentEvents() {
        return [
            { date:'2026-03-12', text:'정기 점검 완료' },
            { date:'2025-10-15', text:'예방 정비 완료' },
            { date:'2024-10-15', text:'서비스 작업 완료' }
        ];
    }

    // Drawer
    get drawerClass() {
        if (this.drawerMinimized) return 'drawer minimized';
        return this.drawerOpen ? 'drawer open' : 'drawer';
    }
    get scrimClass() { return this.drawerOpen && !this.drawerMinimized ? 'scrim open' : 'scrim'; }

    handleOpenDrawer() {
        this.drawerOpen = true;
        this.drawerMinimized = false;
    }
    handleCloseDrawer() { this.drawerOpen = false; this.drawerMinimized = false; }
    handleMinDrawer() { this.drawerMinimized = !this.drawerMinimized; }
    handleScrimClick() { this.handleCloseDrawer(); }

    // T5-23 (2026-08-31 최종): MIAW를 LWR 사이트 Head Markup에 직접
    // 임베드하는 공식 경로로 붙는 데 성공(VF/iframe/새 창 우회책은 전부
    // 불필요해져서 제거 — 경위는 T5_서비스에이전트_작업기록.md 참고).
    // 남은 문제는 LWC가 Lightning Web Security로 격리돼 있어
    // `window.embeddedservice_bootstrap`을 직접 호출할 수 없다는 것 —
    // 실측 확인(같은 페이지에서도 LWC 쪽 window와 최상위 window가
    // 다르게 보임). 그래서 표준 DOM 이벤트로 최상위 페이지(Head Markup
    // 스크립트, LWS 밖에 있음)에 "채팅 열어줘"만 알리고, 실제 API 호출은
    // 그쪽에서 하도록 다리를 놓는다.
    // T5-23: LWC(LWS 안)에서 localStorage를 읽으면 LWS 샌드박스
    // 네임스페이스의 localStorage가 반환되어 MIAW JWT가 안 보인다.
    // 해결: Head Markup(LWS 밖)이 uid를 추출해 'ot_uid_ready' 이벤트로
    // 돌려주고, LWC는 그 uid를 받아 @AuraEnabled Apex를 호출한다.
    connectedCallback() {
        this._uidHandler = (e) => {
            const { uid, assetId } = e.detail || {};
            if (uid && assetId) {
                // eslint-disable-next-line no-console
                console.log('[T5-23] uid received, scheduling Apex calls at +0s/+4s/+8s', uid);
                const delays = [0, 4000, 8000];
                delays.forEach((delay) => {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        // eslint-disable-next-line no-console
                        console.log(`[T5-23] Apex call attempt at +${delay}ms`);
                        setAssetContextFromLwc({ uid, assetId }).catch((err) => {
                            // eslint-disable-next-line no-console
                            console.error('[T5-23] 자산 컨텍스트 전달 실패', err);
                        });
                    }, delay);
                });
            }
        };
        document.addEventListener('ot_uid_ready', this._uidHandler);
    }

    disconnectedCallback() {
        if (this._uidHandler) {
            document.removeEventListener('ot_uid_ready', this._uidHandler);
        }
    }

    handleLaunchChat() {
        // eslint-disable-next-line no-console
        console.log('[T5-23] handleLaunchChat called, assetId=', this.assetId);
        try {
            const evt = new CustomEvent('ot_launch_chat', {
                bubbles: true,
                composed: true,
                detail: { assetId: this.assetId }
            });
            document.dispatchEvent(evt);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('채팅 시작 이벤트 전달 실패', e);
        }
    }

    // Navigation
    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'Home' }
        });
    }
    handleGoTrend() { this.activeTab = 'trend'; }
    handleGoService() { this.activeTab = 'service'; }
}