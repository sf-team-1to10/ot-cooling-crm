import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const PAGE_SIZE = 7;

const DEMO_ASSETS = [
    { id:'CDU-A-07', type:'냉각수 분배 장치', family:'Liquid Cooling CDU', loc:'Hall A · 3열', row:'3열', stateCode:'adv', stateLabel:'P3 Advisory / 주의',
      assess:{ hl:'냉수 유량 기준선 대비 낮음', ds:'냉수 유량이 기준선보다 낮은 상태로 관찰되고 있습니다. 즉시 위험 수준은 아니며 정밀 점검을 권고합니다.', flow:'71 L/min', base:'95–115 L/min' },
      key:{ run:'정상 운전', asset:'P3 Advisory', flow:'71 L/min', dp:'148 kPa', supply:'18.2°C', next:'2026-06-12', flowWarn:true, assetWarn:true },
      trend:{ from:112, to:71, band:[95,115] },
      health:{ score:82, label:'관찰 필요', sub:[{name:'유량 안정성',value:72},{name:'정비 이력',value:91},{name:'서비스 상태',value:95}] },
      alarms:[{ tag:'adv', text:'P3 Advisory · CHW Flow 기준선 대비 낮음', date:'2026-03-12' },{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }] },
    { id:'CDU-A-01', type:'냉각수 분배 장치', family:'Liquid Cooling CDU', loc:'Hall A · 1열', row:'1열', stateCode:'ok', stateLabel:'정상',
      assess:{ hl:'정상 운전 중', ds:'모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.', flow:'104 L/min', base:'95–115 L/min' },
      key:{ run:'정상 운전', asset:'정상', flow:'104 L/min', dp:'132 kPa', supply:'17.9°C', next:'2026-06-12', flowWarn:false, assetWarn:false },
      trend:{ from:103, to:104, band:[95,115] },
      health:{ score:96, label:'양호', sub:[{name:'유량 안정성',value:95},{name:'정비 이력',value:96},{name:'서비스 상태',value:98}] },
      alarms:[{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }] },
    { id:'CDU-A-02', type:'액체-액체 CDU', family:'Liquid-to-Liquid CDU', loc:'Hall A · 1열', row:'1열', stateCode:'ok', stateLabel:'정상',
      assess:{ hl:'정상 운전 중', ds:'모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.', flow:'58 L/min', base:'50–65 L/min' },
      key:{ run:'정상 운전', asset:'정상', flow:'58 L/min', dp:'121 kPa', supply:'18.0°C', next:'2026-06-12', flowWarn:false, assetWarn:false },
      trend:{ from:57, to:58, band:[50,65] },
      health:{ score:94, label:'양호', sub:[{name:'유량 안정성',value:93},{name:'정비 이력',value:94},{name:'서비스 상태',value:96}] },
      alarms:[{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }] },
    { id:'CDU-A-03', type:'랙형 냉각 장치', family:'Rear-Door Cooling Unit', loc:'Hall A · 2열', row:'2열', stateCode:'ok', stateLabel:'정상',
      assess:{ hl:'정상 운전 중', ds:'모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.', flow:'47 L/min', base:'40–55 L/min' },
      key:{ run:'정상 운전', asset:'정상', flow:'47 L/min', dp:'96 kPa', supply:'18.4°C', next:'2026-06-12', flowWarn:false, assetWarn:false },
      trend:{ from:46, to:47, band:[40,55] },
      health:{ score:93, label:'양호', sub:[{name:'유량 안정성',value:92},{name:'정비 이력',value:93},{name:'서비스 상태',value:95}] },
      alarms:[{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }] },
    { id:'CDU-A-04', type:'대용량 액체-액체 CDU', family:'High-Capacity L2L CDU', loc:'Hall A · 2열', row:'2열', stateCode:'ok', stateLabel:'정상',
      assess:{ hl:'정상 운전 중', ds:'모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.', flow:'138 L/min', base:'125–150 L/min' },
      key:{ run:'정상 운전', asset:'정상', flow:'138 L/min', dp:'156 kPa', supply:'17.7°C', next:'2026-06-12', flowWarn:false, assetWarn:false },
      trend:{ from:137, to:138, band:[125,150] },
      health:{ score:95, label:'양호', sub:[{name:'유량 안정성',value:94},{name:'정비 이력',value:95},{name:'서비스 상태',value:97}] },
      alarms:[{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }] },
    { id:'CX-01', type:'냉각 모듈 확장형', family:'Cooling Module Expansion', loc:'Hall A · 보조 존', row:'보조 존', stateCode:'ok', stateLabel:'정상',
      assess:{ hl:'정상 운전 중', ds:'프리쿨링 모듈이 기준선 범위 내에서 안정적으로 관찰되고 있습니다.', flow:'210 L/min', base:'190–230 L/min' },
      key:{ run:'정상 운전', asset:'정상', flow:'210 L/min', dp:'168 kPa', supply:'19.1°C', next:'2026-06-12', flowWarn:false, assetWarn:false },
      trend:{ from:208, to:210, band:[190,230] },
      health:{ score:97, label:'양호', sub:[{name:'유량 안정성',value:96},{name:'정비 이력',value:97},{name:'서비스 상태',value:98}] },
      alarms:[{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }] }
];

// Fill remaining assets for 16 total
(function() {
    const CDU = '냉각수 분배 장치';
    const L2L = 'Liquid Cooling CDU';
    const extras = [
        ['CDU-A-05',CDU,L2L,'Hall A · 3열','3열',107,[95,115],129,'18.0°C',95],
        ['CDU-A-06',CDU,L2L,'Hall A · 3열','3열',99,[95,115],124,'18.1°C',94],
        ['CDU-A-08',CDU,L2L,'Hall A · 4열','4열',141,[125,150],154,'17.8°C',96],
        ['CDU-A-09',CDU,L2L,'Hall A · 4열','4열',106,[95,115],131,'17.9°C',95],
        ['CDU-A-10',CDU,L2L,'Hall A · 5열','5열',137,[125,150],152,'17.7°C',96],
        ['CDU-A-11',CDU,L2L,'Hall A · 5열','5열',57,[50,65],120,'18.2°C',93],
        ['CDU-A-12',CDU,L2L,'Hall A · 5열','5열',103,[95,115],128,'18.0°C',94],
        ['CX-02','냉각 모듈 확장형','Cooling Module Expansion','Hall A · 보조 존','보조 존',205,[190,230],165,'19.0°C',96],
        ['CX-03','냉각 모듈 확장형','Cooling Module Expansion','Hall A · 보조 존','보조 존',212,[190,230],170,'19.2°C',97],
        ['CX-04','냉각 모듈 확장형','Cooling Module Expansion','Hall A · 보조 존','보조 존',198,[190,230],162,'19.1°C',96]
    ];
    extras.forEach(e => {
        DEMO_ASSETS.push({
            id:e[0], type:e[1], family:e[2], loc:e[3], row:e[4],
            stateCode:'ok', stateLabel:'정상',
            assess:{ hl:'정상 운전 중', ds:'모든 지표가 기준선 범위 내에서 안정적으로 관찰되고 있습니다.', flow:`${e[5]} L/min`, base:`${e[6][0]}–${e[6][1]} L/min` },
            key:{ run:'정상 운전', asset:'정상', flow:`${e[5]} L/min`, dp:`${e[7]} kPa`, supply:e[8], next:'2026-06-12', flowWarn:false, assetWarn:false },
            trend:{ from:e[5]-1, to:e[5], band:e[6] },
            health:{ score:e[9], label:'양호', sub:[{name:'유량 안정성',value:e[9]-1},{name:'정비 이력',value:e[9]},{name:'서비스 상태',value:Math.min(99,e[9]+2)}] },
            alarms:[{ tag:'info', text:'Info · 정기 점검 예정 (2026-06-12)', date:'2026-02-20' }]
        });
    });
    DEMO_ASSETS.sort((a,b) => {
        if ((a.stateCode==='adv') !== (b.stateCode==='adv')) return a.stateCode==='adv' ? -1 : 1;
        const pa = a.id.startsWith('CX') ? 1 : 0;
        const pb = b.id.startsWith('CX') ? 1 : 0;
        if (pa !== pb) return pa - pb;
        return a.id.localeCompare(b.id, undefined, {numeric:true});
    });
})();

const DEMO_LOC = { customerName:'아이언데이터센터', siteName:'마이클라우드 데이터센터', hall:'Hall A' };

export default class OtEquipDashboard extends NavigationMixin(LightningElement) {
    @track assets = DEMO_ASSETS;
    @track selectedId = 'CDU-A-07';
    @track currentPage = 1;
    @track activeSubTab = '개요';
    @track searchTerm = '';
    @track modalOpen = false;
    location = DEMO_LOC;

    get filteredAssets() {
        if (!this.searchTerm) return this.assets;
        const q = this.searchTerm.toLowerCase();
        return this.assets.filter(a =>
            a.id.toLowerCase().includes(q) ||
            a.type.toLowerCase().includes(q) ||
            a.loc.toLowerCase().includes(q)
        );
    }

    get totalPages() { return Math.max(1, Math.ceil(this.filteredAssets.length / PAGE_SIZE)); }

    get pageItems() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredAssets.slice(start, start + PAGE_SIZE).map(a => ({
            ...a,
            rowClass: a.id === this.selectedId ? 'eqrow on' : 'eqrow',
            chipVariant: a.stateCode === 'adv' ? 'adv' : 'ok',
            chipLabel: a.stateCode === 'adv' ? '주의' : '정상'
        }));
    }

    get pagerButtons() {
        const btns = [];
        for (let i = 1; i <= this.totalPages; i++) {
            btns.push({ num: i, cls: i === this.currentPage ? 'pg on' : 'pg' });
        }
        return btns;
    }
    get prevDisabled() { return this.currentPage <= 1; }
    get nextDisabled() { return this.currentPage >= this.totalPages; }

    get sel() {
        return this.assets.find(a => a.id === this.selectedId) || this.assets[0];
    }

    get isAdvisory() { return this.sel.stateCode === 'adv'; }
    get assessStyle() {
        return this.isAdvisory
            ? 'assess adv-border'
            : 'assess ok-border';
    }
    get assessIconStyle() {
        return this.isAdvisory ? 'ttl adv-color' : 'ttl ok-color';
    }

    get keyItems() {
        const k = this.sel.key;
        return [
            { label:'운전 상태', value:k.run, cls:'ki-val ok-text' },
            { label:'자산 상태', value:k.asset, cls: k.assetWarn ? 'ki-val warn-text' : 'ki-val ok-text' },
            { label:'CHW Flow', value:k.flow, cls: k.flowWarn ? 'ki-val warn-mono' : 'ki-val mono' },
            { label:'ΔP', value:k.dp, cls:'ki-val mono' },
            { label:'공급수 온도', value:k.supply, cls:'ki-val mono' },
            { label:'다음 정비', value:k.next, cls:'ki-val mono' }
        ];
    }

    // SVG trend chart
    get trendSvg() {
        const tr = this.sel.trend;
        const W=460, H=150, pL=34, pR=10, pT=12, pB=22;
        const iw=W-pL-pR, ih=H-pT-pB;
        const vmin=Math.min(tr.to, tr.band[0])-12;
        const vmax=Math.max(tr.from, tr.band[1])+12;
        const y = v => pT + ih - (v-vmin)/(vmax-vmin)*ih;
        const x = (i,n) => pL + i/(n-1)*iw;
        const n=8;
        const pts=[];
        for(let i=0;i<n;i++){
            const t=i/(n-1);
            const base=tr.from + (tr.to-tr.from)*Math.pow(t,1.4);
            const wob=Math.sin(i*1.7)*1.6;
            pts.push(base+wob);
        }
        pts[n-1]=tr.to;
        let d='', area='';
        for(let i=0;i<n;i++){
            d+=(i?'L':'M')+x(i,n).toFixed(1)+' '+y(pts[i]).toFixed(1)+' ';
        }
        area=d+'L'+x(n-1,n).toFixed(1)+' '+y(vmin).toFixed(1)+' L'+pL+' '+y(vmin).toFixed(1)+' Z';
        const bandTop=y(tr.band[1]), bandBot=y(tr.band[0]);
        let gridHtml='';
        [vmin,(vmin+vmax)/2,vmax].forEach(v => {
            const ty=y(v);
            gridHtml+=`<line x1="${pL}" y1="${ty.toFixed(1)}" x2="${W-pR}" y2="${ty.toFixed(1)}" stroke="#E4E9F3"/>`;
            gridHtml+=`<text x="${pL-6}" y="${(ty+3).toFixed(1)}" text-anchor="end" font-size="9" fill="#96A1B8">${Math.round(v)}</text>`;
        });
        const xl=['-8h','-6h','-4h','-2h','현재'];
        xl.forEach((lb,q) => {
            const xx=pL+q/(xl.length-1)*iw;
            gridHtml+=`<text x="${xx.toFixed(1)}" y="${H-6}" text-anchor="middle" font-size="9" fill="#96A1B8">${lb}</text>`;
        });
        const last=x(n-1,n), lastY=y(tr.to);
        return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" style="width:100%">`+
            `<rect x="${pL}" y="${bandTop.toFixed(1)}" width="${iw}" height="${(bandBot-bandTop).toFixed(1)}" fill="#E7F6EF"/>`+
            `<line x1="${pL}" y1="${bandTop.toFixed(1)}" x2="${W-pR}" y2="${bandTop.toFixed(1)}" stroke="#8FCFB0" stroke-dasharray="3 3"/>`+
            `<line x1="${pL}" y1="${bandBot.toFixed(1)}" x2="${W-pR}" y2="${bandBot.toFixed(1)}" stroke="#8FCFB0" stroke-dasharray="3 3"/>`+
            gridHtml+
            `<path d="${area}" fill="rgba(46,107,230,.08)"/>`+
            `<path d="${d}" fill="none" stroke="#2E6BE6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`+
            `<circle cx="${last.toFixed(1)}" cy="${lastY.toFixed(1)}" r="3.5" fill="#2E6BE6" stroke="#fff" stroke-width="1.5"/>`+
            `<text x="${(last-6).toFixed(1)}" y="${(lastY-8).toFixed(1)}" text-anchor="end" font-size="10" font-weight="700" fill="#1A2540">${tr.to}</text>`+
            `</svg>`;
    }
    get trendLegend() {
        const b = this.sel.trend.band;
        return `CHW Flow (L/min) · 기준선 ${b[0]}–${b[1]}`;
    }

    // Health donut
    get healthScore() { return this.sel.health.score; }
    get healthLabel() { return this.sel.health.label; }
    get healthSubs() { return this.sel.health.sub; }
    get donutSvg() {
        const score = this.healthScore;
        const r=34, c=2*Math.PI*r, off=c*(1-score/100);
        const col = score>=90 ? '#17A566' : (score>=80 ? '#B67611' : '#D14C3F');
        return `<svg viewBox="0 0 88 88" style="width:88px;height:88px">`+
            `<circle cx="44" cy="44" r="${r}" fill="none" stroke="#E4E9F3" stroke-width="9"/>`+
            `<circle cx="44" cy="44" r="${r}" fill="none" stroke="${col}" stroke-width="9" stroke-linecap="round" `+
            `stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}" transform="rotate(-90 44 44)"/>`+
            `</svg>`;
    }

    // KPIs
    get kpiTotal() { return this.assets.length; }
    get kpiNormal() { return this.assets.filter(a => a.stateCode === 'ok').length; }
    get kpiAdvisory() { return this.assets.filter(a => a.stateCode === 'adv').length; }
    get kpiMaintenance() { return 3; }

    // Sub-tab state
    get isOverview() { return this.activeSubTab === '개요'; }
    get isNotOverview() { return this.activeSubTab !== '개요'; }
    get isNormal() { return this.sel.stateCode !== 'adv'; }
    get subTabPlaceholder() {
        const msgs = {
            '성능':'성능 추세 상세는 데모 범위에서 개요 탭의 유량 추세로 대표합니다.',
            '알람':'알람 이력 상세는 장비 상세 화면에서 확인할 수 있습니다.',
            '정비':'정비 일정 및 이력 상세는 장비 상세 화면에서 확인할 수 있습니다.',
            '이력':'자산 변경·인수 이력 상세는 장비 상세 화면에서 확인할 수 있습니다.',
            '문서':'장비 문서(도면·매뉴얼·보증서)는 장비 상세 화면에서 확인할 수 있습니다.'
        };
        return msgs[this.activeSubTab] || '';
    }

    get subTabs() {
        const tabs = ['개요','성능','알람','정비','이력','문서'];
        return tabs.map(t => ({ label: t, cls: t === this.activeSubTab ? 'stab on' : 'stab' }));
    }

    // Handlers
    handleSelectAsset(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.activeSubTab = '개요';
    }
    handlePrevPage() { if (this.currentPage > 1) this.currentPage--; }
    handleNextPage() { if (this.currentPage < this.totalPages) this.currentPage++; }
    handlePage(event) { this.currentPage = parseInt(event.currentTarget.dataset.num, 10); }
    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1;
    }
    handleSubTab(event) { this.activeSubTab = event.currentTarget.dataset.tab; }

    handleGoDetail() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: `/asset-detail?assetId=${this.selectedId}` }
        });
    }
    handleServiceRequest() { this.modalOpen = true; }
    handleModalClose() { this.modalOpen = false; }
    handleModalGoDetail() {
        this.modalOpen = false;
        this.handleGoDetail();
    }

    renderedCallback() {
        const trendEl = this.template.querySelector('.chart-container');
        if (trendEl && this.isOverview) {
            trendEl.innerHTML = this.trendSvg;
        }
        const donutEl = this.template.querySelector('.donut-container');
        if (donutEl) {
            donutEl.innerHTML = this.donutSvg;
        }
    }
}
