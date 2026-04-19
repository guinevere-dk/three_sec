# Merge Benchmark Report Template (v1)

## 실행 시트

| run_id | dataset | run_index | trace_id | ab_group | retry_plan | command |
|---|---|---:|---|---|---|---|
| c5f...01 | photo_silent | 1 | a1b... | A | default | python run_one.py --dataset photo_silent --run-id c5f...01 |
| c5f...02 | photo_silent | 2 | a1b... | A | default | python run_one.py --dataset photo_silent --run-id c5f...02 |

## 결과 시트

| dataset | merge_attempts | merge_success | merge_fail_export_failed | merge_fail_force_stop_external | export_elapsed_ms_p50 | export_elapsed_ms_p95 | retry_overhead_ms | result_exists_rate | result_nonzero_bytes_rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| photo_silent | 30 | 27 | 2 | 1 | 1240 | 1880 | 310 | 96.30% | 96.30% |
| video_audio_mixed | 30 | 25 | 3 | 2 | 1420 | 2130 | 350 | 92.59% | 92.59% |
| video_only | 30 | 26 | 1 | 3 | 1320 | 2050 | 280 | 96.30% | 96.30% |
| **총계** | 90 | 78 | 6 | 6 | 1320 | 2050 | 313 | 94.36% | 94.36% |

### 수집 로그 규칙(요약)

- `normalizedFailCode`, `normalizedFailSource`
- `merge_trace` 또는 `traceId`
- `attempt`, `abGroup`, `retryPlan`, `audioSimplify`
- `resultExists`, `resultBytes`, `exportElapsedMs`
- `EXTERNAL_FORCE_STOP`

## 사용 예시

```bash
python tools/merge_benchmark_pipeline.py --log-dir logs/benchmark --runs-per-dataset 10
python tools/merge_benchmark_report.py --log-dir logs/benchmark --out benchmark/merge_benchmark_v1.md
```
