import { LightningElement, api, wire } from 'lwc';
import { gql, graphql } from 'lightning/uiGraphQLApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';

// 목업(작업기록/ChatGPT Image 2026년 9월 2일) 화면1 "메인 - 오늘 일정" 재현.
// FSM 모바일 앱 홈 탭용. Apex 없이 GraphQL wire로 오늘 일정을 읽는다.
export default class T5FieldHome extends LightningElement {
    @api greeting = '안녕하세요';
    @api subtitle = '오늘도 안전한 하루 되세요!';
    @api brandLabel = 'OT전자';

    userName;
    appointments = [];

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.userName = getFieldValue(data, NAME_FIELD);
        }
    }

    @wire(graphql, {
        query: gql`
            query TodayAppointments {
                uiapi {
                    query {
                        ServiceAppointment(
                            first: 50
                            orderBy: { SchedStartTime: { order: ASC } }
                        ) {
                            edges {
                                node {
                                    Id
                                    AppointmentNumber { value }
                                    Subject { value }
                                    Status { value }
                                    SchedStartTime { value }
                                    SchedEndTime { value }
                                }
                            }
                        }
                    }
                }
            }
        `
    })
    wiredAppointments({ data }) {
        if (!data) {
            return;
        }
        const edges = data.uiapi?.query?.ServiceAppointment?.edges ?? [];
        this.appointments = edges
            .map(edge => this.toAppointment(edge.node))
            .filter(appt => appt.isToday);
    }

    toAppointment(node) {
        const start = node.SchedStartTime?.value;
        const end = node.SchedEndTime?.value;
        const status = node.Status?.value;
        const done = status === 'Completed';
        return {
            id: node.Id,
            number: node.AppointmentNumber?.value,
            subject: node.Subject?.value,
            status,
            statusLabel: done ? '완료' : '예정',
            badgeClass: done ? 'badge badge_done' : 'badge badge_planned',
            timeRange: `${this.formatTime(start)} - ${this.formatTime(end)}`,
            isToday: this.isToday(start)
        };
    }

    isToday(value) {
        if (!value) {
            return false;
        }
        const d = new Date(value);
        const now = new Date();
        return (
            d.getFullYear() === now.getFullYear() &&
            d.getMonth() === now.getMonth() &&
            d.getDate() === now.getDate()
        );
    }

    formatTime(value) {
        if (!value) {
            return '—';
        }
        return new Date(value).toLocaleTimeString('ko-KR', {
            hour: 'numeric',
            minute: '2-digit'
        });
    }

    get greetingLine() {
        return this.userName ? `${this.greeting}, ${this.userName}님` : this.greeting;
    }

    get countLabel() {
        return `오늘 ${this.appointments.length}건`;
    }

    get hasAppointments() {
        return this.appointments.length > 0;
    }
}
