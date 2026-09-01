import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import SYMPTOM_CATEGORY from '@salesforce/schema/Case.Symptom_Category__c';
import REPORTED_SYMPTOM from '@salesforce/schema/Case.Reported_Symptom__c';
import IMPACT_LEVEL from '@salesforce/schema/Case.Impact_Level__c';
import REMOTE_DIAGNOSIS from '@salesforce/schema/Case.Remote_Diagnosis__c';
import FIELD_VISIT from '@salesforce/schema/Case.Field_Visit_Required__c';
import AGENT_FIRST_RESPONSE from '@salesforce/schema/Case.Agent_First_Response_At__c';
import AGENT_HANDOFF from '@salesforce/schema/Case.Agent_Handoff_At__c';

import WARRANTY_DECISION from '@salesforce/schema/Case.Warranty_Decision__c';
import COVERAGE_TYPE from '@salesforce/schema/Case.Coverage_Type__c';
import BILLABLE from '@salesforce/schema/Case.Billable__c';
import WARRANTY_END from '@salesforce/schema/Case.Warranty_End_Date_At_Request__c';
import WARRANTY_JUDGED from '@salesforce/schema/Case.Warranty_Judged_At__c';

// 신설 시각 2필드(AGENT_FIRST_RESPONSE/AGENT_HANDOFF)는 org 스키마 캐시가 갱신되면
// 아래 배열에 다시 추가한다. 현재는 캐시 미반영으로 getRecord 전체가 실패하는 것을 막기 위해 제외.
const FIELDS = [
    SYMPTOM_CATEGORY,
    REPORTED_SYMPTOM,
    IMPACT_LEVEL,
    REMOTE_DIAGNOSIS,
    FIELD_VISIT,
    WARRANTY_DECISION,
    COVERAGE_TYPE,
    BILLABLE,
    WARRANTY_END,
    WARRANTY_JUDGED
];

export default class T5CaseIntakePanel extends LightningElement {
    @api recordId;

    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.record = undefined;
        }
    }

    get isLoading() {
        return !this.record && !this.error;
    }

    get errorMessage() {
        return this.error?.body?.message || 'Case 데이터를 불러오지 못했습니다.';
    }

    // ── Agent가 수집한 내용 ──
    get symptomCategory() {
        return getFieldValue(this.record, SYMPTOM_CATEGORY);
    }
    get reportedSymptom() {
        return getFieldValue(this.record, REPORTED_SYMPTOM);
    }
    get impactLevel() {
        return getFieldValue(this.record, IMPACT_LEVEL);
    }
    get remoteDiagnosis() {
        return getFieldValue(this.record, REMOTE_DIAGNOSIS);
    }
    get fieldVisitRequired() {
        return getFieldValue(this.record, FIELD_VISIT);
    }
    get agentFirstResponse() {
        return this.record?.fields?.Agent_First_Response_At__c
            ? getFieldValue(this.record, AGENT_FIRST_RESPONSE)
            : undefined;
    }
    get agentHandoff() {
        return this.record?.fields?.Agent_Handoff_At__c
            ? getFieldValue(this.record, AGENT_HANDOFF)
            : undefined;
    }
    // 신설 시각 필드가 wire 결과에 실제로 실려 있을 때만 시각 블록을 렌더한다.
    get handoffTimesAvailable() {
        return !!(this.record?.fields?.Agent_First_Response_At__c
            || this.record?.fields?.Agent_Handoff_At__c);
    }

    // ── 보증·SLA 판정 ──
    get warrantyDecision() {
        return getFieldValue(this.record, WARRANTY_DECISION);
    }
    get coverageType() {
        return getFieldValue(this.record, COVERAGE_TYPE);
    }
    get billable() {
        return getFieldValue(this.record, BILLABLE);
    }
    get billableLabel() {
        return this.billable ? '유상' : '무상';
    }
    get warrantyEndDate() {
        return getFieldValue(this.record, WARRANTY_END);
    }
    get warrantyJudgedAt() {
        return getFieldValue(this.record, WARRANTY_JUDGED);
    }

    get selfDiagnosisUnresolved() {
        // 원격 진단 결과가 있으면 자가조치가 수행됐다는 의미 — 미해결 배지 표시
        return !!this.remoteDiagnosis;
    }
}
