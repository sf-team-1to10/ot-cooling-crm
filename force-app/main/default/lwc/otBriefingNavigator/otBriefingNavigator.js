import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { IsConsoleNavigation } from 'lightning/platformWorkspaceApi';
import { openOrFocusSubtab } from 'c/otConsoleNav';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CASE_NUMBER from '@salesforce/schema/Case.CaseNumber';

/**
 * Flow screen 컴포넌트. 출동 브리핑 생성 Flow의 마지막 화면에 배치되어,
 * 현재 Case 워크스페이스 주탭 아래에 브리핑 App Page를 서브탭으로 연다.
 * 케이스 → 브리핑 생성 → 브리핑 확인 흐름을 하나의 Case 작업공간에서 이어간다.
 */
export default class OtBriefingNavigator extends NavigationMixin(LightningElement) {
    @api recordId;

    @wire(IsConsoleNavigation) isConsoleNavigation;

    @wire(getRecord, { recordId: '$recordId', fields: [CASE_NUMBER] })
    caseRecord;

    get caseNumber() {
        return getFieldValue(this.caseRecord.data, CASE_NUMBER);
    }

    get isConsole() {
        return this.isConsoleNavigation?.data === true;
    }

    async handleOpen() {
        if (!this.recordId) {
            return;
        }
        const target = 'c__otDispatchBriefingWorkbench';

        if (this.isConsole) {
            await openOrFocusSubtab(target, this.recordId);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: target },
                state: { c__recordId: this.recordId }
            });
        }
    }
}