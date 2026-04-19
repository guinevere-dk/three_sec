# Merge Benchmark v1 Report

자동 로그 파서로 집계한 결과입니다.

- 생성 시각(UTC): 2026-04-06T13:19:39.928885+00:00
- 파싱 로그 파일 수: 0

## KPI 계산 정의
- `merge_attempts`: 전체 병합 시도 수
- `merge_success`: 결과가 성공으로 마무리된 트레이스 수
- `merge_fail_export_failed`: 비정상 종료를 포함하지 않는 실패 트레이스 수
- `merge_fail_force_stop_external`: EXTERNAL_FORCE_STOP로 판단되는 실패 트레이스 수
- `export_elapsed_ms_p50/p95`: 성공 트레이스 기준 소요시간 p50/p95
- `retry_overhead_ms`: retry이 발생한 트레이스의 attempt2-attempt1
- `result_exists_rate`: 성공 트레이스 중 resultExists=true 비율
- `result_nonzero_bytes_rate`: 성공 트레이스 중 resultBytes>0 비율

## Dataset Summary
| dataset | merge_attempts | merge_success | merge_fail_export_failed | merge_fail_force_stop_external | export_elapsed_ms_p50 | export_elapsed_ms_p95 | retry_overhead_ms | result_exists_rate | result_nonzero_bytes_rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|

## Overall Summary

| KPI | Value |
|---|---:|
| merge_attempts | 0 |
| merge_success | 0 |
| merge_fail_export_failed | 0 |
| merge_fail_force_stop_external | 0 |
| export_elapsed_ms_p50 | - |
| export_elapsed_ms_p95 | - |
| retry_overhead_ms | - |
| result_exists_rate | 0.00% |
| result_nonzero_bytes_rate | 0.00% |
