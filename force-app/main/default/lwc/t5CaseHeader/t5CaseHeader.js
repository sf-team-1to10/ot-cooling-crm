import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { IsConsoleNavigation } from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getHeader from '@salesforce/apex/T5CaseHeaderController.getHeader';

export default class T5CaseHeader extends NavigationMixin(LightningElement) {
    @api recordId;
    @api caseId;

    get effectiveRecordId() {
        return this.caseId || this.recordId;
    }

    @wire(IsConsoleNavigation) isConsoleNavigation;

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    header;
    error;

    @wire(getHeader, { caseId: '$effectiveRecordId' })
    wiredHeader({ data, error }) {
        if (data) {
            this.header = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.header = undefined;
        }
    }

    get isLoading() {
        return !this.header && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'Case 헤더를 불러오지 못했습니다.';
    }

    get accountName() {
        return this.header?.accountName || '';
    }

    get headerTitle() {
        return this.header?.subject || '';
    }

    get status() {
        return this.header?.status || '';
    }

    get caseNumber() {
        return this.header?.caseNumber || '';
    }

    get assetName() {
        return this.header?.assetName || '';
    }

    get agentFirstResponseText() {
        return this.formatTime(this.header?.agentFirstResponseAt);
    }

    get agentHandoffText() {
        return this.formatTime(this.header?.agentHandoffAt);
    }

    get responseSla() {
        return this.header?.responseSla || '—';
    }

    get recoverySla() {
        return this.header?.recoverySla || '—';
    }

    formatTime(raw) {
        if (!raw) {
            return '—';
        }
        return new Date(raw).toLocaleTimeString('ko-KR', {
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    showBriefingFlow = false;
    flowLoaded = false;

    get flowLoading() {
        return !this.flowLoaded;
    }

    get cardClass() {
        return this.flowLoaded ? 'briefing-card' : 'briefing-card briefing-card_hidden';
    }

    get flowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.effectiveRecordId }];
    }

    flowError = false;

    handleBriefing() {
        this.flowLoaded = false;
        this.flowError = false;
        this.showBriefingFlow = true;
    }

    async handleSubtab(event) {
        const componentName = event.currentTarget.dataset.goto;
        this.navigate(componentName);
    }

    async navigate(target) {
        if (!target || !this.effectiveRecordId) {
            return;
        }
        if (this.isConsole) {
            await openOrFocusSubtab(target, this.effectiveRecordId);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: this.effectiveRecordId }
            });
        }
    }

    closeBriefingFlow() {
        this.showBriefingFlow = false;
        this.flowLoaded = false;
    }

    handleOverlayClick() {
        this.closeBriefingFlow();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleFlowStatusChange(event) {
        const status = event.detail.status;
        if (status === 'ERROR') {
            this.flowError = true;
            this.flowLoaded = true;
            return;
        }
        this.flowLoaded = true;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.showBriefingFlow = false;
            this.flowLoaded = false;
            getRecordNotifyChange([{ recordId: this.effectiveRecordId }]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '출동 브리핑 생성 완료',
                    message: '브리핑 본문과 유사사례가 기록됐습니다.',
                    variant: 'success'
                })
            );
        }
    }
}
