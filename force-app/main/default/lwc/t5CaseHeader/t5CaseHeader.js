import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getHeader from '@salesforce/apex/T5CaseHeaderController.getHeader';

export default class T5CaseHeader extends LightningElement {
    @api recordId;

    header;
    error;
    showBriefingFlow = false;
    flowLoaded = false;

    get flowLoading() {
        return !this.flowLoaded;
    }

    // 로딩 중엔 카드를 숨기고(Flow는 DOM 유지) 스피너만, 로드 후 카드 표시
    get cardClass() {
        return this.flowLoaded ? 'briefing-card' : 'briefing-card briefing-card_hidden';
    }

    @wire(getHeader, { caseId: '$recordId' })
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
        return this.error?.body?.message || '헤더 데이터를 불러오지 못했습니다.';
    }

    get caseNumber() {
        return this.header?.caseNumber;
    }

    get accountName() {
        return this.header?.accountName || '고객';
    }

    get assetName() {
        return this.header?.assetName || '—';
    }

    get status() {
        return this.header?.status;
    }

    // 프로토타입 4번 장면 타이틀 — {Asset} {증상 분류} (예: "CDU-A-07 유량 저하")
    get headerTitle() {
        const asset = this.header?.assetName;
        const symptom = this.header?.symptomCategory;
        const parts = [asset, symptom].filter((p) => p);
        return parts.length ? parts.join(' ') : this.header?.subject || 'Case';
    }

    get responseSla() {
        return this.header?.responseSla || '—';
    }

    get recoverySla() {
        return this.header?.recoverySla || '—';
    }

    // Agent 시각 2필드 — 캐시 미반영 시 '준비중'으로 degrade
    get agentFirstResponseText() {
        return this.toTime(this.header?.agentFirstResponseAt);
    }

    get agentHandoffText() {
        return this.toTime(this.header?.agentHandoffAt);
    }

    toTime(raw) {
        if (!raw) {
            return '준비중';
        }
        return new Date(raw).toLocaleTimeString('ko-KR', {
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    // 표준 QuickAction(Case.Dispatch_Briefing_Generate)과 동일한 Screen Flow를 모달로 실행
    get flowInputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.recordId }];
    }

    handleBriefing() {
        this.flowLoaded = false;
        this.showBriefingFlow = true;
    }

    closeBriefingFlow() {
        this.showBriefingFlow = false;
        this.flowLoaded = false;
    }

    // overlay(모달 밖) 클릭 시 닫기. 카드 안 클릭은 stopPropagation으로 여기 도달 안 함.
    handleOverlayClick() {
        this.closeBriefingFlow();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleFlowStatusChange(event) {
        const status = event.detail.status;
        // Flow가 첫 화면을 렌더하면(STARTED/PAUSED/FINISHED_SCREEN) 로딩 종료로 간주 —
        // 이때부터 닫기 버튼 표시 + content 높이를 콘텐츠에 맞게 확장한다.
        if (status !== 'ERROR') {
            this.flowLoaded = true;
        }
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.showBriefingFlow = false;
            this.flowLoaded = false;
            // Flow가 기록한 Dispatch_Briefing__c 등 최신값을 화면에 반영
            getRecordNotifyChange([{ recordId: this.recordId }]);
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
