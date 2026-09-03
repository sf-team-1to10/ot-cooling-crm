import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CASE_STAGE from '@salesforce/schema/Case.Stage__c';

/**
 * 공용 프로세스 진행률 바.
 *
 * 오브젝트별 stage 정의는 아래 STAGE_MAP에 하드코딩. 데모용이라
 * "장면이 정해져 있음" 원칙(실행지침 §4 참고).
 *
 * 우선순위:
 *   1) App Builder에서 currentStep을 0 이상으로 세팅한 경우 — 그 값 사용
 *   2) recordId가 있고 sobjectType이 STAGE_MAP에 있으면 — 필드 자동 읽음
 *   3) 둘 다 아니면 — 전체 pending
 */
const STAGE_MAP = {
    Case: {
        field: CASE_STAGE,
        steps: [
            { num: '0', label: '접수' },
            { num: '1', label: '진단·브리핑' },
            { num: '2', label: '담당자 배정' },
            { num: '3', label: '현장 출동' },
            { num: '4', label: '수리·복구' },
            { num: '5', label: 'RCA·예방·지식' }
        ]
    }
    // 다른 오브젝트는 필요 시 추가
};

const PREFIX_TO_OBJECT = {
    '500': 'Case',
    '0WO': 'WorkOrder',
    '0PB': 'Problem',
    '800': 'ServiceContract'
};

export default class OtProcessPath extends LightningElement {
    @api recordId;
    @api objectType;
    @api currentStep = -1;

    _stageValue;

    get resolvedObjectType() {
        if (this.objectType) return this.objectType;
        if (!this.recordId) return null;
        const prefix = String(this.recordId).slice(0, 3);
        return PREFIX_TO_OBJECT[prefix] || null;
    }

    get stageDef() {
        return STAGE_MAP[this.resolvedObjectType] || null;
    }

    get stageField() {
        return this.stageDef?.field ? [this.stageDef.field] : [];
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$stageField' })
    wiredRecord({ data }) {
        if (data && this.stageDef?.field) {
            this._stageValue = getFieldValue(data, this.stageDef.field);
        }
    }

    get resolvedCurrentIndex() {
        if (this.currentStep !== null && this.currentStep !== undefined && this.currentStep >= 0) {
            return Number(this.currentStep);
        }
        if (!this._stageValue) return -1;
        const first = String(this._stageValue).trim().split(/\s+/)[0];
        const idx = parseInt(first, 10);
        return Number.isNaN(idx) ? -1 : idx;
    }

    get steps() {
        const def = this.stageDef;
        if (!def) return [];
        const cur = this.resolvedCurrentIndex;
        return def.steps.map((s, i) => {
            let state = 'pending';
            if (i < cur) state = 'done';
            else if (i === cur) state = 'current';
            return {
                key: s.num,
                num: s.num,
                label: s.label,
                cls: `step step--${state}`,
                iconCls: `step__icon step__icon--${state}`,
                showCheck: state === 'done'
            };
        });
    }

    get hasSteps() {
        return this.steps.length > 0;
    }
}
