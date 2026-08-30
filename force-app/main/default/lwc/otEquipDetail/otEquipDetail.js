import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

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

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        if (ref && ref.state && ref.state.assetId) {
            this.assetId = ref.state.assetId;
        }
    }

    get assetName() { return 'CDU-A-07'; }
    get assetMeta() { return '냉각수 분배 장치 · Liquid Cooling CDU · Hall A · 3열 · Serial No. OTC-CW-120-A07 · 설치일 2022-06-18'; }

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
            { cap:'3/4 스튜디오 뷰', badge:'대표 이미지' },
            { cap:'정면 뷰', badge:'' },
            { cap:'도어 오픈 · 내부 배관', badge:'' },
            { cap:'후면 배관 인터페이스', badge:'' },
            { cap:'설치 현장', badge:'' }
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

    // Condition rows
    get conditionRows() {
        return [
            { label:'운전 상태', value:'정상 운전', cls:'val teal' },
            { label:'자산 상태', value:'P3 Advisory / 주의', cls:'val amber' },
            { label:'관찰 항목', value:'CHW Flow 기준선 대비 낮음', cls:'val' },
            { label:'현재값', value:'71 L/min', cls:'val amber mono' },
            { label:'운전 기준선', value:'95–115 L/min', cls:'val mono' },
            { label:'Advisory 지속', value:'45분', cls:'val mono' },
            { label:'마지막 데이터 수신', value:'02:59 · 데모', cls:'val mono' }
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
            g+=`<line x1="${pL}" y1="${Y(v).toFixed(1)}" x2="${W-pR}" y2="${Y(v).toFixed(1)}" stroke="#E9EEF6"/>`;
            g+=`<text x="${pL-8}" y="${(Y(v)+3).toFixed(1)}" text-anchor="end" font-size="9.5" fill="#95A0B7">${(Math.round(v*10)/10)}</text>`;
        });
        const xl=RANGES[this.curRange];
        xl.forEach((lb,q) => {
            const xx=pL+q/(xl.length-1)*iw;
            g+=`<text x="${xx.toFixed(1)}" y="${H-12}" text-anchor="middle" font-size="9.5" fill="#95A0B7">${lb}</text>`;
        });
        const bandY1=Y(M.band[1]), bandY0=Y(M.band[0]);
        const last=X(n-1), lastY=Y(pts[n-1]);
        el.innerHTML=`<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" style="width:100%">`+
            `<rect x="${pL}" y="${bandY1.toFixed(1)}" width="${iw}" height="${(bandY0-bandY1).toFixed(1)}" fill="#E6F3EF"/>`+
            `<line x1="${pL}" y1="${bandY0.toFixed(1)}" x2="${W-pR}" y2="${bandY0.toFixed(1)}" stroke="#63B79A" stroke-dasharray="5 3"/>`+
            `<line x1="${pL}" y1="${bandY1.toFixed(1)}" x2="${W-pR}" y2="${bandY1.toFixed(1)}" stroke="#9FCFBD" stroke-dasharray="4 4"/>`+
            g+
            `<path d="${area}" fill="rgba(46,107,230,.07)"/>`+
            `<path d="${d}" fill="none" stroke="#2E6BE6" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`+
            `<circle cx="${last.toFixed(1)}" cy="${lastY.toFixed(1)}" r="4" fill="#2E6BE6" stroke="#fff" stroke-width="1.6"/>`+
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

    // T5-23: MIAW를 LWR 사이트에 직접 임베드하면 "No targetElement specified"
    // 에러로 실패(2026-08-30/31 실측 — CSP/CORS/v1↔v2/Lightning Web Security
    // on-off/Deployment 재생성까지 다 시도해도 재현, T5_서비스에이전트_작업기록.md
    // 참고). Visualforce는 이 문제가 없어(공식 Test Enhanced Web Chat에서 실측
    // 확인) VF 페이지를 iframe으로 감싸는 우회책을 쓴다.
    get chatEmbedUrl() {
        return '/otcustomer/apex/T5AgentChatEmbed';
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
