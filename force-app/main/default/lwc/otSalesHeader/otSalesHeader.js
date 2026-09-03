import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';

export default class OtSalesHeader extends LightningElement {
    userName;

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD] })
    wiredUser({ data }) {
        if (data) this.userName = getFieldValue(data, NAME_FIELD);
    }

    get greeting() {
        const now = new Date();
        const days = ['일', '월', '화', '수', '목', '금', '토'];
        const y = now.getFullYear();
        const m = now.getMonth() + 1;
        const d = now.getDate();
        const dayName = days[now.getDay()];
        const name = this.userName || '';
        const hour = now.getHours();
        let timeGreeting = 'Good morning';
        if (hour >= 12 && hour < 18) timeGreeting = 'Good afternoon';
        else if (hour >= 18) timeGreeting = 'Good evening';
        return `${timeGreeting}, ${name}. — ${y}년 ${m}월 ${d}일 (${dayName})`;
    }
}