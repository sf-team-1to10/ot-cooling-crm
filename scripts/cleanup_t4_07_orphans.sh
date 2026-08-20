#!/bin/bash
# AssetId 없는 WOLI(자동생성 Flow 수정 전 생긴 것) 삭제 — 시계열 정리용. 실행 전 check_t4_07_org.sh 7번으로 대상 확인할 것
set -eu
ORG=T4OPS
sf data query -o $ORG -q "SELECT Id FROM WorkOrderLineItem WHERE AssetId = null" -r csv > /tmp/orphan_woli.csv
echo "삭제 대상: $(($(wc -l < /tmp/orphan_woli.csv)-1))건"
sf data delete bulk -s WorkOrderLineItem -f /tmp/orphan_woli.csv -o $ORG --wait 5

# 실패한 seed가 남긴 [시딩] WorkOrder도 제거 (라인 먼저 지운 뒤)
sf data query -o $ORG -q "SELECT Id FROM WorkOrder WHERE Subject LIKE '[시딩]%'" -r csv > /tmp/seed_wo.csv
echo "[시딩] WO 삭제 대상: $(($(wc -l < /tmp/seed_wo.csv)-1))건"
sf data delete bulk -s WorkOrder -f /tmp/seed_wo.csv -o $ORG --wait 5
