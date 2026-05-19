# Cloud Clip Policy Decision v1

## 1. Subscription Expiry Policy
- 만료 즉시 신규 upload/copy 차단
- 기존 Cloud clip은 30일 동안 read/download 허용
- 30일 이후 read 차단
- 90일 이후 deletion candidate로 분류
- 실제 삭제는 dry-run manifest + 수동 승인 후에만 가능

## 2. Cloud Copy Policy
- MVP에서는 Cloud-to-Cloud copy 미구현
- 사용자는 다운로드 후 재추가 방식만 허용
- Cloud copy는 v2 기능으로 분리

## 3. Storage Deletion Policy
- 현재 단계에서는 실제 삭제 금지
- dry-run inventory만 허용
- manifest에는 object path, owner, project, reason, expected usage delta 포함
- execute delete는 별도 승인 후 구현

## 4. Migration/Backfill Policy
- 기존 사용자 문서 mutation 금지
- inventory dry-run 먼저 수행
- staged rollout 전까지 fallback 유지

## 5. Firebase Rules/Index Policy
- rules 완화 금지
- emulator 테스트 계정 기반 deny/allow case 검증 후 최소 변경만 허용