import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STAGE_FIELD from '@salesforce/schema/Case.Stage__c';

// 프로토타입 v-briefing 6단계. 라벨은 Case.Stage__c 값 앞의 숫자와 1:1로 정렬.
const STEPS = [
    { num: '0', label: '접수' },
    { num: '1', label: '진단·브리핑' },
    { num: '2', label: '담당자 배정' },
    { num: '3', label: '현장 출동' },
    { num: '4', label: '수리·복구' },
    { num: '5', label: 'RCA·예방·지식' }
];

export default class OtCasePath extends LightningElement {
    @api recordId;

    _stage;

    @wire(getRecord, { recordId: '$recordId', fields: [STAGE_FIELD] })
    wiredCase({ data }) {
        if (data) {
            this._stage = getFieldValue(data, STAGE_FIELD);
        }
    }

    // "3 현장 출동" 형태에서 앞 숫자만 뽑는다. Stage 값이 없으면 -1(모두 pending).
    get currentIndex() {
        if (!this._stage) return -1;
        const first = this._stage.trim().split(/\s+/)[0];
        const idx = parseInt(first, 10);
        return Number.isNaN(idx) ? -1 : idx;
    }

    // 현재 stage보다 낮은 index → done, 같으면 on, 높으면 pending
    get steps() {
        const cur = this.currentIndex;
        return STEPS.map((s, i) => {
            let cls = 'path-step';
            if (i < cur) cls += ' done';
            else if (i === cur) cls += ' on';
            return { key: s.num, num: s.num, label: s.label, cls };
        });
    }
}
