import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { IsConsoleNavigation } from 'lightning/platformWorkspaceApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import getCaseId   from '@salesforce/apex/OtMsCaseWorkController.getCaseId';
import getCaseHeader from '@salesforce/apex/T5CaseHeaderController.getHeader';

export default class OtMsCaseWorkPanel extends NavigationMixin(LightningElement) {
    @api recordId; // MessagingSession Id

    @wire(IsConsoleNavigation) isConsoleNavigation;

    // ── CaseId 조회 ──
    caseId;
    _caseIdLoaded = false;
    _caseIdError;

    @wire(getCaseId, { sessionId: '$recordId' })
    wiredCaseId({ data, error }) {
        if (data !== undefined) {
            this.caseId = data || null;
            this._caseIdLoaded = true;
            this._caseIdError = undefined;
        } else if (error) {
            this._caseIdError = error;
            this._caseIdLoaded = true;
        }
    }

    // ── Case 헤더 조회 (caseId 확보 후 reactive) ──
    caseHeader;
    _caseHeaderError;

    @wire(getCaseHeader, { caseId: '$caseId' })
    wiredCaseHeader({ data, error }) {
        if (data) {
            this.caseHeader = data;
            this._caseHeaderError = undefined;
        } else if (error) {
            this._caseHeaderError = error;
            this.caseHeader = undefined;
        }
    }

    // ── 상태 플래그 ──
    get isLoading()         { return !this._caseIdLoaded; }
    get hasError()          { return !!this._caseIdError; }
    get showNoCase()        { return this._caseIdLoaded && !this._caseIdError && !this.caseId; }
    get showCaseWork()      { return this._caseIdLoaded && !this._caseIdError && !!this.caseId; }
    get caseHeaderLoading() { return this.showCaseWork && !this.caseHeader && !this._caseHeaderError; }

    get errorMessage() {
        return this._caseIdError?.body?.message || '데이터를 불러오지 못했습니다.';
    }

    // ── 시간 포맷 ──
    get agentFirstResponseText() { return this._formatTime(this.caseHeader?.agentFirstResponseAt); }
    get agentHandoffText()        { return this._formatTime(this.caseHeader?.agentHandoffAt); }

    _formatTime(raw) {
        if (!raw) return '—';
        return new Date(raw).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
    }

    // ── 서브탭 ──
    get isConsole() { return this.isConsoleNavigation?.data === true; }

    async handleSubtab(event) {
        const target = event.currentTarget.dataset.goto;
        if (!target || !this.caseId) return;
        if (this.isConsole) {
            await openOrFocusSubtab(target, this.caseId);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: this.caseId }
            });
        }
    }

    // ── Case 없을 때 생성 ──
    handleCreateCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' },
            state: { defaultFieldValues: 'Status=New' }
        });
    }

    // ── 출동 브리핑 Flow ──
    showBriefingFlow = false;
    flowLoaded = false;
    flowError = false;

    get flowLoading() { return !this.flowLoaded; }
    get cardClass()   { return this.flowLoaded ? 'briefing-card' : 'briefing-card briefing-card_hidden'; }
    get flowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.caseId }];
    }

    handleBriefing() {
        this.flowLoaded = false;
        this.flowError  = false;
        this.showBriefingFlow = true;
    }

    handleOverlayClick()      { this._closeBriefingFlow(); }
    stopPropagation(event)    { event.stopPropagation(); }
    _closeBriefingFlow()      { this.showBriefingFlow = false; this.flowLoaded = false; }

    handleFlowStatusChange(event) {
        const status = event.detail.status;
        if (status === 'ERROR') {
            this.flowError  = true;
            this.flowLoaded = true;
            return;
        }
        this.flowLoaded = true;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this._closeBriefingFlow();
            getRecordNotifyChange([{ recordId: this.caseId }]);
            this.dispatchEvent(new ShowToastEvent({
                title: '출동 브리핑 생성 완료',
                message: '브리핑 본문과 유사사례가 기록됐습니다.',
                variant: 'success'
            }));
        }
    }
}
