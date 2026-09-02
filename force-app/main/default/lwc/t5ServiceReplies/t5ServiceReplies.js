import { LightningElement } from 'lwc';

const DEFAULT_DATA = {
    contactName: '유신',
    assetName: 'CDU-A-07',
    contractName: '아이온데이터 CDU SLA 보증 계약'
};

const REPLY_OPTIONS = [
    {
        value: 'handoff',
        label: '상담 인수 인사',
        context: '대화 이력 · 장비 상태 기반',
        build: d => `${d.contactName}님 안녕하세요. OT전자 서비스 담당 서정비입니다. `
            + `Service Agent와 확인하신 내용이 모두 전달됐습니다. `
            + `${d.assetName} 유량 1,961 L/min, AUTO 운전, 별도 알람 없음, 차압 0.31 MPa, `
            + `유량 저하 지속 상태로 확인했습니다. `
            + `앞에서 확인하신 내용은 다시 말씀하지 않으셔도 됩니다.`
    },
    {
        value: 'impact',
        label: '운영 영향 확인',
        context: '장비 상태 · 운영 영향 판단',
        build: () => `현재 냉각 성능 저하로 Hall A의 랙 운영을 제한하거나 부하를 낮추신 상태인지 확인 부탁드립니다.`
    },
    {
        value: 'urgency',
        label: '긴급 대응 안내',
        context: '운영 현황 · 긴급도 판단',
        build: () => `확인했습니다. 운영은 유지되고 있지만 유량 저하가 지속되고 있으니 긴급 대응으로 진행하겠습니다.`
    },
    {
        value: 'entitlement',
        label: '계약·보증 확인 안내',
        context: 'Service Contract · Warranty 조회',
        build: d => `${d.contactName}님, 계약과 보증 상태도 확인했습니다. `
            + `${d.assetName}은 ${d.contractName}와 Warranty가 모두 유효하고, `
            + `이번 장애는 계약상 서비스 대상입니다. `
            + `긴급 대응 SLA도 확인되어 바로 현장 출동을 진행하겠습니다.`
    },
    {
        value: 'dispatch',
        label: '출동 확정 안내',
        context: '출동 배정 · SLA 확인',
        build: () => `기사님은 15:30 도착 예정입니다. `
            + `현장에서 원인을 확인한 뒤 Warranty 적용 여부와 최종 작업 범위도 함께 판단하겠습니다. `
            + `도착 전까지는 장비를 직접 조작하지 않고 현재 상태를 유지해 주세요.`
    },
    {
        value: 'recovery',
        label: '복구 상태 확인',
        context: '현장 조치 결과 · 유량 복구 확인',
        build: d => `${d.contactName}님, 현재까지 유량이 2,080 L/min으로 안정적으로 유지되고 있습니다. `
            + `현장에서도 추가 이상 징후는 확인되지 않았습니다. `
            + `설비 운영에도 문제가 없는지 마지막으로 확인 부탁드립니다.`
    },
    {
        value: 'confirm',
        label: '복구 완료 확인',
        context: '복구 확인 · SLA 달성 판정',
        build: () => `확인 감사합니다. 복구 확인이 완료되었습니다. `
            + `이번 건은 계약상 복구 목표시간인 8시간 이내에 정상화됐습니다. `
            + `원인 분석과 재발 방지 조치를 정리한 뒤 Case를 종결하겠습니다.`
    },
    {
        value: 'prevention',
        label: '예방점검 안내',
        context: '원인 분석 · 동종 장비 비교',
        build: d => `${d.contactName}님, 이번 장애 원인을 분석한 결과 `
            + `${d.assetName}에서 과거 작업이 있었던 접합부가 다시 점검이 필요한 상태로 확인됐습니다. `
            + `예정된 정기점검은 10월 15일이지만, 동일한 조건의 장비는 그때까지 기다리지 않고 `
            + `별도의 예방점검을 진행하기로 했습니다. `
            + `${d.assetName}을 제외한 동일 대상 장비 11대에 대해서도 선제적으로 점검을 진행할 예정입니다.`
    },
    {
        value: 'preventionFollow',
        label: '예방점검 후속 안내',
        context: '예방점검 계획 확인',
        build: () => `네. 이번 장애를 개별 장비의 수리로 끝내지 않고, `
            + `동일 문제가 반복되지 않도록 예방점검까지 연결하겠습니다.`
    },
    {
        value: 'closing',
        label: '최종 결과 안내',
        context: '조치 결과 · SLA · 재발 방지 종합',
        build: d => `${d.contactName}님, 이번 서비스 건의 최종 결과를 안내드리겠습니다.\n\n`
            + `[조치 결과]\n`
            + `${d.assetName} 배관 접합부(F-07) 재조임 완료\n`
            + `유량 2,080 L/min으로 회복 · 정상 운영 확인\n`
            + `계약 및 Warranty 범위 처리 · 고객 청구 없음\n\n`
            + `[SLA]\n`
            + `복구 목표: 8시간 이내\n`
            + `실제 복구 확인: 4시간 10분\n`
            + `SLA: 충족\n\n`
            + `[재발 방지]\n`
            + `동일 조건 11대 예방점검 예정\n`
            + `해당 접합부 확인 항목 점검표 추가 (Rev.2 → Rev.3)\n`
            + `향후 정기점검에 개정 기준 적용`
    },
    {
        value: 'closingFinal',
        label: 'Case 종결 안내',
        context: 'Case 종결 판단',
        build: () => `복구 확인과 후속 예방조치 등록까지 완료되어 Case를 종결합니다.`
    }
];

const GENERATING_DELAY = 1500;

export default class T5ServiceReplies extends LightningElement {
    _selectedValue = null;
    _state = 'select';
    _copied = false;

    get comboboxOptions() {
        return REPLY_OPTIONS.map(o => ({ label: o.label, value: o.value }));
    }

    get isSelect() {
        return this._state === 'select';
    }

    get isGenerating() {
        return this._state === 'generating';
    }

    get hasReply() {
        return this._state === 'reply';
    }

    get cannotGenerate() {
        return !this._selectedValue;
    }

    get selectedOption() {
        return REPLY_OPTIONS.find(o => o.value === this._selectedValue);
    }

    get contextLabel() {
        const opt = this.selectedOption;
        return opt ? opt.context : '';
    }

    get replyText() {
        const opt = this.selectedOption;
        return opt ? opt.build(DEFAULT_DATA) : '';
    }

    get copyLabel() {
        return this._copied ? '복사됨 ✓' : '채팅에 사용';
    }

    handleComboChange(event) {
        this._selectedValue = event.detail.value;
        this._state = 'select';
        this._copied = false;
    }

    handleGenerate() {
        if (!this._selectedValue) return;
        this._state = 'generating';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this._state = 'reply';
        }, GENERATING_DELAY);
    }

    handleCopy() {
        navigator.clipboard.writeText(this.replyText).then(() => {
            this._copied = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this._copied = false; }, 1500);
        });
    }

    handleBack() {
        this._state = 'select';
        this._copied = false;
    }
}
