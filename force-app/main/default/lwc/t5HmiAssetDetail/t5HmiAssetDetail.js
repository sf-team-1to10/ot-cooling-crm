import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import getAssetDetail from '@salesforce/apex/T5HmiAssetDetailController.getAssetDetail';
import acknowledgeAlert from '@salesforce/apex/T5HmiAssetDetailController.acknowledgeAlert';
import isServiceAgentEnabled from '@salesforce/apex/OtTrendAlertCardController.isServiceAgentEnabled';
import userId from '@salesforce/user/Id';

const USER_FIELDS = ['User.Name', 'User.Contact.Account.Name'];

// T5-23: MIAW(Embedded Messaging for Web) 연결 정보 — Setup > Messaging
// Settings > OT_Service_Chat 채널의 Code Snippet 화면에서 그대로 복사(2026-08-30).
// 이 값들은 org별로 다르므로 Production 이관 시 재확인 필요
// (T5_Production_이관_체크리스트.md B-7 참고).
const MIAW_ORG_ID = '00Dh800000046bV';
const MIAW_ES_DEVELOPER_NAME = 'OT_Service_Chat';
const MIAW_SITE_URL = 'https://trailsignup-8617b18a6871a9--t3dlv.sandbox.my.site.com/ESWOTServiceCha1788104812895';
const MIAW_SCRT2_URL = 'https://trailsignup-8617b18a6871a9--t3dlv.sandbox.my.salesforce-scrt.com';
const MIAW_BOOTSTRAP_SRC = `${MIAW_SITE_URL}/assets/js/bootstrap.min.js`;

// 모듈 스코프에 둬서 컴포넌트가 여러 번 렌더링돼도 SDK를 중복 로드/초기화하지
// 않도록 한다(embeddedservice_bootstrap은 전역 객체라 두 번 init하면 안 됨).
let miawScriptLoading = null;
let miawReady = false;

export default class T5HmiAssetDetail extends NavigationMixin(LightningElement) {
    @api assetId;

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (pageRef?.state?.assetId) {
            this.assetId = pageRef.state.assetId;
        }
    }

    detail;
    error;
    loaded = false;
    activeTab = 'info';
    showDrawer = false;
    showModal = false;
    showToast = false;
    toastMessage = '';
    exportMsg = '';
    chatMessages = [];
    _chatCounter = 0;
    wiredDetailResult;
    userName = '';
    userCompany = '';
    _tempSparkRendered = false;

    // T5-11: 상담/채팅 진입 버튼(위치·이름 미정, UI 담당이 별도 작업 중) 게이팅용.
    // 이 컴포넌트 어디에 버튼을 두든 lwc:if={agentEnabled}만 걸면 된다 —
    // 마크업이 바뀌어도 이 로직은 그대로 재사용된다. 기본값 false로 시작해서
    // wire 응답 전까지는 fail-closed(RG-10).
    agentEnabled = false;

    @wire(isServiceAgentEnabled)
    wiredAgentFlag({ data }) {
        this.agentEnabled = !!data;
    }

    @wire(getRecord, { recordId: userId, fields: USER_FIELDS })
    wiredUser({ data }) {
        if (data) {
            this.userName = data.fields.Name.value || '';
            const acct = data.fields.Contact?.value?.fields?.Account?.value;
            this.userCompany = acct?.fields?.Name?.value || '';
        }
    }

    @wire(getAssetDetail, { assetId: '$assetId' })
    wiredDetail(result) {
        this.wiredDetailResult = result;
        const { data, error } = result;
        if (error) {
            this.loaded = true;
            this.detail = undefined;
            this.error = this.reduceError(error);
            return;
        }
        if (data === undefined) return;
        this.loaded = true;
        this.error = undefined;
        this.detail = data;
        this._tempSparkRendered = false;
    }

    renderedCallback() {
        if (!this._tempSparkRendered && this.detail && this.isInfoTab === false) {
            this.renderTempSparkline();
        }
        if (!this._tempSparkRendered && this.detail) {
            this.renderTempSparkline();
        }
    }

    renderTempSparkline() {
        const container = this.template.querySelector('.temp-spark');
        if (!container) return;
        const arr = [6.9, 6.88, 6.85, 6.83, 6.82, 6.8, 6.81, 6.8, 6.8, 6.79, 6.8, 6.8, 6.8];
        const color = '#3E86BE';
        const w = 200, h = 22, n = arr.length;
        const mn = Math.min(...arr), mx = Math.max(...arr);
        const rng = (mx - mn) || 1;
        const pts = arr.map((v, i) =>
            `${((i / (n - 1)) * w).toFixed(1)},${(h - 3 - ((v - mn) / rng) * (h - 6)).toFixed(1)}`
        ).join(' ');
        const last = pts.split(' ').pop().split(',');
        container.innerHTML =
            `<svg viewBox="0 0 200 22" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">` +
            `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linejoin="round"/>` +
            `<circle cx="${last[0]}" cy="${last[1]}" r="2" fill="${color}"/>` +
            `</svg>`;
        this._tempSparkRendered = true;
    }

    // ── Tab ──────────────────────────────────────────────────────────────
    switchTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        this._tempSparkRendered = false;
    }

    // ── Overlay handlers ────────────────────────────────────────────────
    // T5-23: 목업 드로어 대신 실제 MIAW(Embedded Messaging) 위젯을 띄운다.
    // 채팅 UI 자체는 Salesforce 기본 위젯을 그대로 쓰기로 결정(2026-08-30) —
    // 포털 화면이 곧 재설계될 예정이라 커스텀 UI 통합(Custom UI Components)에
    // 투자하지 않고, 지금은 실제 기능 연결만 검증한다.
    openChat() {
        this.loadMiawSdk()
            .then(() => this.launchMiawChat())
            .catch((e) => {
                // eslint-disable-next-line no-console
                console.error('MIAW 로드 실패', e);
            });
    }

    loadMiawSdk() {
        if (miawReady) {
            return Promise.resolve();
        }
        if (miawScriptLoading) {
            return miawScriptLoading;
        }
        miawScriptLoading = new Promise((resolve, reject) => {
            window.addEventListener('onEmbeddedMessagingReady', () => {
                miawReady = true;
                resolve();
            }, { once: true });

            if (window.embeddedservice_bootstrap) {
                // 이미 다른 컴포넌트/이전 렌더에서 스크립트가 로드된 경우.
                this.initMiaw();
                return;
            }

            const script = document.createElement('script');
            script.type = 'text/javascript';
            script.src = MIAW_BOOTSTRAP_SRC;
            script.onload = () => this.initMiaw();
            script.onerror = (e) => reject(e);
            document.body.appendChild(script);
        });
        return miawScriptLoading;
    }

    initMiaw() {
        try {
            window.embeddedservice_bootstrap.settings.language = 'ko';
            // 기본 플로팅 버튼은 숨기고, 우리 "상담 시작" 버튼으로만 연다.
            window.embeddedservice_bootstrap.settings.hideChatButtonOnLoad = true;
            window.embeddedservice_bootstrap.init(
                MIAW_ORG_ID,
                MIAW_ES_DEVELOPER_NAME,
                MIAW_SITE_URL,
                { scrt2URL: MIAW_SCRT2_URL }
            );
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Error loading Embedded Messaging: ', e);
        }
    }

    launchMiawChat() {
        const bootstrap = window.embeddedservice_bootstrap;
        if (!bootstrap) return;
        // API 표기가 SDK 버전에 따라 다르게 문서화돼 있어(utilAPI.launchChat vs
        // launchChat) 둘 다 방어적으로 시도한다(2026-08-30, 공식 문서 확인 시
        // 두 표기가 혼재돼 있었음).
        if (bootstrap.utilAPI && typeof bootstrap.utilAPI.launchChat === 'function') {
            bootstrap.utilAPI.launchChat();
        } else if (typeof bootstrap.launchChat === 'function') {
            bootstrap.launchChat();
        } else {
            // eslint-disable-next-line no-console
            console.error('launchChat API를 찾을 수 없음 — SDK 버전 확인 필요');
        }
    }

    openModal() { this.showModal = true; this.showDrawer = false; }
    closeAll() { this.showDrawer = false; this.showModal = false; }
    switchToModal() { this.showDrawer = false; this.showModal = true; }

    handleKeydown(event) {
        if (event.key === 'Escape') this.closeAll();
    }

    // ── Chat (demo) ─────────────────────────────────────────────────────
    handleChatKey(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.sendChat();
        }
    }

    sendChat() {
        const input = this.template.querySelector('.chat-msg-input');
        if (!input) return;
        const v = input.value.trim();
        if (!v) return;
        this._chatCounter++;
        // isBot(불리언)으로 통일 — 예전엔 class={m.isMe}로 불리언을 그대로
        // class 속성에 바인딩해서 class="true"/"false"가 찍히는 버그가 있었다
        // (2026-08-30 위젯 재작업하며 같이 수정, .chat-msg bot/me 두 갈래로
        // lwc:if 분기).
        this.chatMessages = [
            ...this.chatMessages,
            { text: v, isBot: false, id: `me-${this._chatCounter}` }
        ];
        input.value = '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this._chatCounter++;
            this.chatMessages = [
                ...this.chatMessages,
                {
                    text: '접수되었습니다. 자산 상태와 서비스 이력을 함께 확인하여 OT전자 서비스팀이 안내드리겠습니다. (데모 응답)',
                    isBot: true,
                    id: `bot-${this._chatCounter}`
                }
            ];
        }, 500);
    }

    get assetNameForGreeting() {
        return this.detail?.asset?.name || '이 자산';
    }

    // ── Acknowledge alert ───────────────────────────────────────────────
    handleAcknowledge() {
        if (!this.detail?.alert?.alertId) return;
        acknowledgeAlert({ alertId: this.detail.alert.alertId })
            .then(() => refreshApex(this.wiredDetailResult))
            .catch(() => {});
    }

    // ── Service request (demo) ──────────────────────────────────────────
    submitModal() {
        this.toastMessage = '서비스 요청이 접수되었습니다. 담당자가 검토 후 안내드립니다.';
        this.showToast = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showToast = false; }, 4000);
    }

    // ── Export (demo) ───────────────────────────────────────────────────
    handleExport(event) {
        const type = event.currentTarget.dataset.type;
        const name = this.detail?.asset?.name || '';
        this.exportMsg = type === 'pdf'
            ? `${name} 상태 리포트(PDF) 생성을 요청했습니다. 준비되면 알림으로 전달됩니다.`
            : `${name} 계측·이력 데이터(CSV) 내보내기를 요청했습니다. 준비되면 알림으로 전달됩니다.`;
    }

    // ── Navigate back ───────────────────────────────────────────────────
    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'Home' }
        });
    }

    // ── Getters ─────────────────────────────────────────────────────────
    get isLoading() { return !!this.assetId && !this.loaded; }
    get hasNoAssetId() { return !this.assetId; }
    get hasError() { return !!this.error; }
    get hasDetail() { return !!this.detail?.asset && !this.error; }
    get hasAlert() { return !!this.detail?.alert; }
    get isInfoTab() { return this.activeTab === 'info'; }
    get isHistTab() { return this.activeTab === 'hist'; }
    get showExportMsg() { return !!this.exportMsg; }

    get infoTabClass() { return 'tab-btn' + (this.isInfoTab ? ' active' : ''); }
    get histTabClass() { return 'tab-btn' + (this.isHistTab ? ' active' : ''); }

    get assetSubline() {
        const a = this.detail?.asset;
        if (!a) return '';
        return [a.siteLocation, a.productName].filter(Boolean).join(' · ');
    }

    get inspectionDday() {
        const d = this.detail?.asset?.nextInspectionDate;
        if (!d) return null;
        const diff = Math.ceil((new Date(d) - new Date()) / 86400000);
        if (diff > 0) return `D-${diff}`;
        if (diff === 0) return 'D-DAY';
        return `지연 ${Math.abs(diff)}일`;
    }

    get alertDurationText() {
        const s = this.detail?.alert?.startedAt;
        if (!s) return '';
        const mins = Math.floor((Date.now() - new Date(s).getTime()) / 60000);
        if (mins < 60) return `${mins}분 지속`;
        return `${Math.floor(mins / 60)}시간 ${mins % 60}분 지속`;
    }

    get alertSignalSub() {
        const a = this.detail?.alert;
        if (!a) return '';
        return `${a.currentValueText || ''} (기준 ${a.normalRangeText || ''}) · ${this.alertDurationText}`;
    }

    get alertSignalTitle() {
        const name = this.detail?.asset?.name || '';
        const msg = this.detail?.alert?.message || '상태 이상이 감지됐습니다';
        return `${name} ${msg}`;
    }

    get hasEntitlement() { return !!this.detail?.entitlement; }

    get entitlementText() {
        const e = this.detail?.entitlement;
        if (!e) return '정보 없음';
        return e.slaProcessName || e.status || '서비스 계약 적용';
    }

    get entitlementEndText() {
        const e = this.detail?.entitlement;
        if (!e?.endDate) return '';
        return `${e.endDate} 만료`;
    }

    get statusPills() {
        const a = this.detail?.asset;
        if (!a) return [];
        const pills = [];
        if (a.latestTrendFlag === '주의' || a.latestTrendFlag === '이상') {
            pills.push({ label: `P3 Advisory`, cls: 'pill adv', key: 'adv' });
        } else {
            pills.push({ label: '정상 운전', cls: 'pill ok', key: 'ok' });
        }
        return pills;
    }

    get openItemsText() {
        const v = this.detail?.asset?.openItemsSummary;
        return v != null ? `${Math.floor(v)}건` : '0건';
    }

    get gaugeConfigs() {
        return [
            {
                key: 'flow',
                title: '2차측 쿨런트 순환 유량계',
                badge: '▲ 하락 경고',
                alertLevel: 'alert',
                value: 745.8, unit: 'L/min',
                gaugeMin: 600, gaugeMax: 900, ticks: 6,
                zones: [{ to: 0.60, color: '#37A94F' }, { to: 0.82, color: '#F2C200' }, { to: 1, color: '#E0322B' }],
                sparkData: [800, 796, 792, 788, 783, 778, 772, 766, 760, 755, 750, 747, 745.8],
                sparkColor: '#D8452F',
                sparkLabel: '실시간 20초 트렌드',
                sparkRef: '기준 800 L/min',
                explain: '최근 45분간 기준선보다 낮은 상태가 지속되고 있습니다.'
            },
            {
                key: 'torque',
                title: '배관 플랜지 체결토크 실측',
                badge: '▼ 이력 편차',
                alertLevel: 'alert',
                value: 71, unit: 'N·m',
                gaugeMin: 40, gaugeMax: 130, ticks: 9,
                zones: [{ to: 0.72, color: '#7EC0E8' }, { to: 0.86, color: '#F2C200' }, { to: 1, color: '#E0322B' }],
                sparkData: [74, 73, 73, 72, 72, 71, 71, 71, 70, 71, 71, 71, 71],
                sparkColor: '#D8452F',
                sparkLabel: '실시간 20초 트렌드',
                sparkRef: '설계선 105–115 N·m',
                explain: '냉수 유량 변화와 함께 확인이 필요한 값입니다.'
            }
        ];
    }

    get decoratedHistory() {
        return (this.detail?.history || []).map(h => ({
            ...h,
            chipClass: 'hist-chip ok',
            chipText: '정상',
            key: h.workOrderNumber || h.title
        }));
    }

    get hasChatMessages() { return this.chatMessages.length > 0; }

    get userInitial() {
        return this.userName ? this.userName.charAt(0) : '?';
    }

    get userChipText() {
        return [this.userName, this.userCompany].filter(Boolean).join(' · ');
    }

    // T5-11 위젯 재작업: 플로팅 챗봇 위젯은 요즘 서비스봇처럼 배경을 안 어둡게
    // 깐다(모달만 어둡게) — scrim을 showModal에만 건다. 배경 클릭으로 채팅이
    // 닫히지 않는 것도 의도된 변화(닫기는 X 버튼으로만).
    get scrimClass() { return 'scrim' + (this.showModal ? ' open' : ''); }
    get drawerClass() { return 'drawer' + (this.showDrawer ? ' open' : ''); }
    get modalClass() { return 'modal' + (this.showModal ? ' open' : ''); }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || '자산 상세 데이터를 불러오지 못했습니다.';
    }
}
