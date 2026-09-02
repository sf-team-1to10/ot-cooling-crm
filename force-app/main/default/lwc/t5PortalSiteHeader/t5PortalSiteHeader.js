import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import ACCOUNT_NAME_FIELD from '@salesforce/schema/User.Contact.Account.Name';
import OT_LOGO_NAVY from '@salesforce/resourceUrl/OT_Logo_Square_Navy';

/**
 * 사이트 전역 헤더(Experience Builder Header 영역 전용, 2026-08-30 신설).
 * 원래 t5HmiAssetHome 자체 헤더에 있던 브랜드/탭/유저칩을 여기로 옮겼다 —
 * "활성 경보" pill만은 옮기지 않았다: 그 아래 실제 배너와 같은
 * Customer_Alert__c 데이터를 써야 하는데, Header 영역과 Page 영역
 * 컴포넌트는 서로 상태를 공유할 방법이 없다(별도 컴포넌트 인스턴스).
 * 바로 아래 페이지 콘텐츠의 상세 배너가 같은 역할을 이미 하고 있어
 * 중복 없이 생략했다.
 */
export default class T5PortalSiteHeader extends LightningElement {
    logoUrl = OT_LOGO_NAVY;
    userName;
    accountName;

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD, ACCOUNT_NAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.userName = getFieldValue(data, NAME_FIELD);
            this.accountName = getFieldValue(data, ACCOUNT_NAME_FIELD);
        }
    }

    get displayName() {
        if (this.userName && this.accountName) {
            return `${this.userName} · ${this.accountName}`;
        }
        return this.userName || this.accountName || '';
    }

    toastMessage = '';
    toastVisible = false;
    toastTimer;

    get toastClass() {
        return this.toastVisible ? 'toast show' : 'toast';
    }

    handleExit() {
        this.toastMessage = '준비 중입니다 — 실제 구현 시 OT전자 메인 홈페이지로 연결됩니다.';
        this.toastVisible = true;
        clearTimeout(this.toastTimer);
        this.toastTimer = setTimeout(() => {
            this.toastVisible = false;
        }, 3200);
    }
}
