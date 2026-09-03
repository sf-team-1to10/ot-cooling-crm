import { LightningElement, track } from "lwc";

export default class OtCoolingHome extends LightningElement {
    @track activeTab = "today";
    @track currentTime = "";
    _timer;

    connectedCallback() {
        this.currentTime = this._now();
        this._timer = setInterval(() => {
            this.currentTime = this._now();
        }, 5000);
    }

    disconnectedCallback() {
        clearInterval(this._timer);
    }

    get isTodayActive() {
        return this.activeTab === "today";
    }

    get isRcaActive() {
        return this.activeTab === "rca";
    }

    get todayTabClass() {
        return this.activeTab === "today" ? "tab-btn active" : "tab-btn";
    }

    get rcaTabClass() {
        return this.activeTab === "rca" ? "tab-btn active" : "tab-btn";
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    _now() {
        const d = new Date();
        const p = (n) => String(n).padStart(2, "0");
        return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
    }
}
