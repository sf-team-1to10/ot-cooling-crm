import { LightningElement, api, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAssetTrendInfo from '@salesforce/apex/OtTrendAlertCardController.getAssetTrendInfo';
import isServiceAgentEnabled from '@salesforce/apex/OtTrendAlertCardController.isServiceAgentEnabled';

/** Platform Event channel published by T5-06's IoT simulator pipeline. */
const IOT_READING_CHANNEL = '/event/IoT_Reading__e';

/**
 * Customer portal Trend card (T5-07). Warning stays Pull (refresh-based) —
 * Critical gets an active signal via a narrow empApi subscription that only
 * triggers a re-fetch, never streams raw values to the customer. See
 * T5_시각화_실시간알림_구조정리.md 3장 for why this is an intentional
 * exception to "no active customer notification", not scope creep.
 */
export default class OtTrendAlertCard extends LightningElement {
    @api assetId;

    trend;
    error;
    showCriticalBanner = false;
    // Apex 호출이 (성공/실패 관계없이) 한 번이라도 끝났는지. data/error가
    // 둘 다 falsy인 상태가 "아직 응답 안 옴"인지 "성공했지만 null 반환"인지
    // 구분하기 위해 필요하다(예: 이 사용자가 어떤 고객사 계정에도 속하지
    // 않는 내부 관리자 — Apex가 정상적으로 null을 반환하고 끝난다).
    loaded = false;

    // T5-11: 서버가 T5_Feature_Flags__mdt.Service_Agent_Enabled__c 값을 준다.
    // 기본값 false로 시작 — wire 응답 전까지는 "안 보이는 쪽"으로 fail-closed.
    agentEnabled = false;

    wiredTrendResult;
    subscription;

    @wire(isServiceAgentEnabled)
    wiredAgentFlag({ data }) {
        this.agentEnabled = !!data;
    }

    // '$assetId' (with the leading $) re-runs the Apex call whenever the
    // assetId property changes, mirroring the @wire pattern used in
    // otMyAssets/otAssetPortal. Captured as `result` (not destructured) so
    // refreshApex() can re-invoke it from the empApi callback below.
    @wire(getAssetTrendInfo, { assetId: '$assetId' })
    wiredTrend(result) {
        this.wiredTrendResult = result;
        const { data, error } = result;
        if (error) {
            this.loaded = true;
            this.trend = undefined;
            this.error = this.reduceError(error);
            return;
        }
        // data가 undefined면 아직 응답이 안 온 것 — 로딩 상태를 유지한다.
        if (data === undefined) {
            return;
        }
        this.loaded = true;
        this.error = undefined;
        const wasAttentionBefore = this.trend?.needsAttention;
        this.trend = data; // null일 수 있음(예: 계정 스코프에 안 걸리는 사용자)
        // Critical 전환 감지 — 새로고침 없이 방금 데이터가 갱신됐고,
        // 지금 상태가 "이상"이면 배너를 띄운다(값 자체를 스트리밍하는 게
        // 아니라 전환 시점 신호만 능동적으로 준다).
        if (data && !wasAttentionBefore && data.needsAttention && data.trendFlag === '이상') {
            this.showCriticalBanner = true;
        }
    }

    connectedCallback() {
        this.subscribeToIotEvents();
    }

    disconnectedCallback() {
        this.unsubscribeFromIotEvents();
    }

    subscribeToIotEvents() {
        subscribe(IOT_READING_CHANNEL, -1, (event) => {
            const payload = event?.data?.payload;
            // 이 Asset과 무관한 이벤트는 무시 — 전체 스트리밍이 아니라
            // 이 카드가 보여주는 자산 하나에 한정된 좁은 구독.
            if (payload && payload.Asset_Id__c === this.assetId) {
                refreshApex(this.wiredTrendResult);
            }
        }).then((response) => {
            this.subscription = response;
        });

        // eslint-disable-next-line no-unused-vars
        onError((error) => {
            // 구독 실패는 조용히 무시 — Critical 배너는 "있으면 좋은" 보강
            // 기능이지, 없다고 카드 자체가 못 뜨면 안 된다(Pull 경로가 항상
            // 안전망으로 남아 있음).
        });
    }

    unsubscribeFromIotEvents() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    dismissBanner() {
        this.showCriticalBanner = false;
    }

    get showAgentButton() {
        return this.agentEnabled && this.hasTrend;
    }

    // T5-11: 지금은 이 assetId를 실제로 받아줄 화면(MIAW 채널=T5-23, Help Agent
    // 배치=T5-16)이 아직 없어서 임시로 토스트에 그대로 되비쳐서 "버튼을 눌렀을 때
    // 이 자산의 assetId가 맞게 넘어간다"를 육안으로 확인하는 용도로만 쓴다.
    // 나중에 T5-23이 붙으면 이 메서드 하나만 실제 진입 로직(NavigationMixin 또는
    // Embedded Messaging 세션 시작)으로 바꾸면 되고, 버튼·Feature Flag 게이팅은
    // 그대로 재사용된다.
    handleAgentConsult() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Agent 상담 (준비 중)',
                message: `이 자산(${this.assetId})으로 Agent 상담을 시작합니다 — 실시간 채팅 연결은 준비 중입니다. 지금은 "장애 신고" 폼을 이용해 주세요.`,
                variant: 'info',
                mode: 'sticky'
            })
        );
    }

    get isLoading() {
        return !!this.assetId && !this.loaded;
    }

    get hasNoAssetId() {
        return !this.assetId;
    }

    get hasError() {
        return !!this.error;
    }

    get hasTrend() {
        return !!this.trend && !this.error;
    }

    // 호출은 성공적으로 끝났지만 trend가 null인 경우 — 예: 이 사용자가
    // 어떤 고객사 계정에도 속하지 않아 계정 스코핑에서 걸러진 경우.
    get hasNoAccess() {
        return this.loaded && !this.trend && !this.error;
    }

    get statusText() {
        return this.trend?.needsAttention ? '● 주의' : '● 정상';
    }

    get statusClass() {
        return this.trend?.needsAttention ? 'st warn' : 'st ok';
    }

    get hasImage() {
        return !!this.trend?.imageUrl;
    }

    get imageUrl() {
        return this.trend?.imageUrl;
    }

    get subline() {
        if (!this.trend) {
            return '';
        }
        const parts = [];
        if (this.trend.productName) {
            parts.push(this.trend.productName);
        }
        if (this.trend.appliedRevision) {
            parts.push(this.trend.appliedRevision);
        }
        if (this.trend.status) {
            parts.push(this.trend.status);
        }
        return parts.join(' · ');
    }

    get gauges() {
        return this.trend?.gauges || [];
    }

    get hasGauges() {
        return this.gauges.length > 0;
    }

    get hasNoGauges() {
        return this.hasTrend && this.gauges.length === 0;
    }

    get shouldShowBanner() {
        return this.showCriticalBanner && this.hasTrend;
    }

    get bannerText() {
        const first = this.gauges[0];
        if (!first) {
            return `${this.trend?.name}에서 이상이 감지됐습니다.`;
        }
        return `${this.trend?.name} — ${first.measurementItemCode} 이상이 감지됐습니다.`;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || '자산 추이 정보를 불러오지 못했습니다.';
    }
}
