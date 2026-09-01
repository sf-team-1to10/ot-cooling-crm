import { LightningElement, api } from 'lwc';

/**
 * 카드/리스트 공용 썸네일. 이미지가 없으면(요구사항 13) 고객운영홈_HMI.html의
 * 원본 SILHOUETTE placeholder SVG를 그대로 보여준다.
 */
export default class T5HmiAssetThumb extends LightningElement {
    @api imageUrl;
    @api alt = '';

    get hasImage() {
        return !!this.imageUrl;
    }
}
