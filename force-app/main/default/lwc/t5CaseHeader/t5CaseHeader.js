import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

export default class T5CaseHeader extends LightningElement {
    @api recordId;

    showBriefingFlow = false;
    flowLoaded = false;

    get flowLoading() {
        return !this.flowLoaded;
    }

    // 로딩 중엔 카드를 숨기고(Flow는 DOM 유지) 스피너만, 로드 후 카드 표시
    get cardClass() {
        return this.flowLoaded ? 'briefing-card' : 'briefing-card briefing-card_hidden';
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
