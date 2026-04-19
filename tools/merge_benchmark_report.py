#!/usr/bin/env python3
"""병합 로그 기반 KPI 집계 리포트 생성기."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


KEY_VALUE_RE = re.compile(r"(?P<key>[A-Za-z0-9_\-]+)=(?P<value>\"[^\"]*\"|[^\s]+)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="merge benchmark log parser",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=Path("logs/benchmark"),
        help="로그 디렉터리",
    )
    parser.add_argument(
        "--schedule",
        type=Path,
        default=None,
        help="벤치마크 실행 계획 JSON(옵션). run_id/traceId 메타 연결용",
    )
    parser.add_argument(
        "--pattern",
        type=str,
        default="*.log",
        help="수집 로그 파일 glob 패턴",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("benchmark/merge_benchmark_v1.md"),
        help="md 리포트 경로",
    )
    parser.add_argument(
        "--include-unassigned",
        action="store_true",
        help="dataset 미식별 로그까지 집계",
    )
    return parser.parse_args()


def parse_key_values(line: str) -> dict:
    parsed = {}
    for match in KEY_VALUE_RE.finditer(line):
        key = match.group("key")
        value = match.group("value")
        if value.startswith('"') and value.endswith('"') and len(value) >= 2:
            value = value[1:-1]
        parsed[key] = value
    return parsed


def to_int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(str(value).strip().split(".")[0])
    except (ValueError, TypeError):
        return None


def to_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    low = str(value).lower()
    if low in ("1", "true", "t", "yes", "y", "on"):
        return True
    if low in ("0", "false", "f", "no", "n", "off"):
        return False
    return None


def is_external_force_stop(payload: dict) -> bool:
    normalized_code = str(payload.get("normalizedFailCode", "")).upper()
    normalized_source = str(payload.get("normalizedFailSource", "")).upper()
    signature = str(payload.get("forceStopSignature", "")).upper()
    details = str(payload.get("details", "")).upper()
    return (
        normalized_code == "EXTERNAL_FORCE_STOP"
        or normalized_source == "EXTERNAL_FORCE_STOP"
        or "EXTERNAL_FORCE_STOP" in signature
        or "EXTERNAL_FORCE_STOP" in details
        or "KILLING" in details
        or "FORCE STOP" in details
    )


def percentile(values: list[int], p: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return float(values[0])
    idx = (len(values) - 1) * p / 100.0
    lo = int(idx)
    hi = lo + 1
    frac = idx - lo
    if hi >= len(values):
        return float(values[-1])
    return values[lo] + (values[hi] - values[lo]) * frac


def read_schedule(path: Path | None) -> tuple[dict[str, dict], dict[str, dict]]:
    if path is None or not path.exists():
        return {}, {}
    with path.open("r", encoding="utf-8") as f:
        payload = json.load(f)

    run_by_run_id: dict[str, dict] = {}
    run_by_trace_id: dict[str, dict] = {}
    for run in payload.get("runs", []) if isinstance(payload, dict) else []:
        if not isinstance(run, dict):
            continue
        run_id = str(run.get("run_id", ""))
        trace_id = str(run.get("trace_id", ""))
        if run_id:
            run_by_run_id[run_id] = run
        if trace_id:
            run_by_trace_id[trace_id] = run
    return run_by_run_id, run_by_trace_id


def format_rate(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return round((numerator / denominator) * 100.0, 2)


def ensure_trace_state(states: dict[str, dict], trace_id: str, run_id: str | None, dataset: str) -> dict:
    if trace_id not in states:
        states[trace_id] = {
            "run_id": run_id,
            "dataset": dataset,
            "attempts": {},
            "latest_attempt": 0,
        }
    return states[trace_id]


def collect_runs(log_dir: Path, pattern: str, *, schedule_run_by_run_id: dict[str, dict], schedule_run_by_trace_id: dict[str, dict], include_unassigned: bool) -> tuple[dict, int, set[str]]:
    states: dict[str, dict] = {}
    matched_files: set[str] = set()

    for path in sorted(log_dir.rglob(pattern)):
        if not path.is_file():
            continue
        matched_files.add(str(path))

        current_run_id: str | None = None
        current_trace_id: str | None = None
        current_dataset: str | None = None

        with path.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                kv = parse_key_values(line)
                if "[Benchmark][Run]" in line and "event=run_start" in line:
                    current_run_id = kv.get("run_id") or kv.get("runId")
                    current_trace_id = kv.get("traceId") or kv.get("trace_id")
                    current_dataset = kv.get("dataset")
                    if not current_dataset and current_run_id:
                        run_meta = schedule_run_by_run_id.get(current_run_id)
                        if isinstance(run_meta, dict):
                            current_dataset = str(run_meta.get("dataset_id", ""))
                    continue

                if "[Benchmark][Run]" in line and "event=run_meta" in line:
                    if not current_run_id:
                        current_run_id = kv.get("run_id") or kv.get("runId")
                    if not current_trace_id:
                        current_trace_id = kv.get("traceId") or kv.get("trace_id")
                    if not current_dataset:
                        current_dataset = kv.get("dataset") or kv.get("dataset_id")
                    continue

                trace_id = kv.get("traceId") or kv.get("trace_id") or kv.get("merge_trace") or kv.get("mergeTrace") or kv.get("trace")
                if not trace_id:
                    trace_id = current_trace_id
                if not trace_id and current_run_id:
                    trace_id = schedule_run_by_run_id.get(current_run_id, {}).get("trace_id") or current_run_id

                dataset = current_dataset
                if not dataset and trace_id:
                    dataset = schedule_run_by_trace_id.get(str(trace_id), {}).get("dataset_id")
                if not dataset:
                    dataset = schedule_run_by_run_id.get(current_run_id or "", {}).get("dataset_id") if current_run_id else None

                if not dataset:
                    dataset = kv.get("dataset") or kv.get("dataset_id") or "unassigned"

                attempt = to_int(kv.get("attempt")) or 1
                normalized = kv.get("normalizedFailCode") or kv.get("normalizedFailSource")

                if "[VideoManager][Export] invoking_merge" in line:
                    state = ensure_trace_state(states, str(trace_id), current_run_id, str(dataset))
                    state.setdefault("attempts", {}).setdefault(attempt, {})
                    st = state["attempts"][attempt]
                    st["attempt"] = attempt
                    st["status"] = "started"
                    st["abGroup"] = kv.get("abGroup") or kv.get("ab_group")
                    st["retryPlan"] = kv.get("retryPlan")
                    state["latest_attempt"] = max(state["latest_attempt"], attempt)
                    if normalized is not None:
                        st["normalizedFailCode"] = normalized
                    continue

                if "[VideoManager][Export] invoke_merge_done" in line:
                    elapsed = to_int(kv.get("exportElapsedMs"))
                    if elapsed is None:
                        elapsed = to_int(kv.get("elapsedMs"))
                    result = kv.get("result")
                    result_exists = to_bool(kv.get("resultExists"))
                    result_bytes = to_int(kv.get("resultBytes"))
                    state = ensure_trace_state(states, str(trace_id), current_run_id, str(dataset))
                    state.setdefault("attempts", {}).setdefault(attempt, {})
                    st = state["attempts"][attempt]
                    st["attempt"] = attempt
                    st["status"] = "success" if (result is not None and result != "null") else "fail"
                    st["elapsed_ms"] = elapsed
                    st["result"] = result
                    st["resultExists"] = bool(result_exists) if result_exists is not None else False
                    st["resultBytes"] = result_bytes
                    state["latest_attempt"] = max(state["latest_attempt"], attempt)
                    continue

                if "[VideoManager][Export][MergeFail]" in line:
                    state = ensure_trace_state(states, str(trace_id), current_run_id, str(dataset))
                    state.setdefault("attempts", {}).setdefault(attempt, {})
                    st = state["attempts"][attempt]
                    elapsed = to_int(kv.get("elapsedMs"))
                    if elapsed is None:
                        elapsed = to_int(kv.get("exportElapsedMs"))
                    st["attempt"] = attempt
                    st["status"] = "fail"
                    st["elapsed_ms"] = elapsed
                    st["normalizedFailCode"] = kv.get("normalizedFailCode")
                    st["normalizedFailSource"] = kv.get("normalizedFailSource")
                    st["forceStopSignature"] = kv.get("forceStopSignature")
                    st["details"] = kv.get("details")
                    st["is_external_force_stop"] = is_external_force_stop(st)
                    state["latest_attempt"] = max(state["latest_attempt"], attempt)
                    continue

                if "[VideoManager][Export][MergeRetry]" in line:
                    state = ensure_trace_state(states, str(trace_id), current_run_id, str(dataset))
                    state.setdefault("attempts", {}).setdefault(attempt, {})
                    st = state["attempts"][attempt]
                    st["retryRequested"] = True
                    st["nextRetryPlan"] = kv.get("nextRetryPlan")
                    continue

    if not include_unassigned:
        states = {k: v for k, v in states.items() if v.get("dataset") != "unassigned"}

    return states, len(matched_files), set()


def build_markdown(payload: dict, matched_files: int) -> str:
    timestamp = datetime.now(tz=timezone.utc).isoformat()
    dataset_order = sorted(payload.keys())

    overall = {
        "merge_attempts": 0,
        "merge_success": 0,
        "merge_fail_export_failed": 0,
        "merge_fail_force_stop_external": 0,
        "success_elapsed_ms": [],
        "retry_overheads": [],
        "result_exists": 0,
        "result_nonzero_bytes": 0,
    }

    lines = [
        "# Merge Benchmark v1 Report",
        "",
        "자동 로그 파서로 집계한 결과입니다.",
        "",
        f"- 생성 시각(UTC): {timestamp}",
        f"- 파싱 로그 파일 수: {matched_files}",
        "",
        "## KPI 계산 정의",
        "- `merge_attempts`: 전체 병합 시도 수",
        "- `merge_success`: 결과가 성공으로 마무리된 트레이스 수",
        "- `merge_fail_export_failed`: 비정상 종료를 포함하지 않는 실패 트레이스 수",
        "- `merge_fail_force_stop_external`: EXTERNAL_FORCE_STOP로 판단되는 실패 트레이스 수",
        "- `export_elapsed_ms_p50/p95`: 성공 트레이스 기준 소요시간 p50/p95",
        "- `retry_overhead_ms`: retry이 발생한 트레이스의 attempt2-attempt1",
        "- `result_exists_rate`: 성공 트레이스 중 resultExists=true 비율",
        "- `result_nonzero_bytes_rate`: 성공 트레이스 중 resultBytes>0 비율",
        "",
    ]

    lines.append("## Dataset Summary")
    lines.append(
        "| dataset | merge_attempts | merge_success | merge_fail_export_failed | merge_fail_force_stop_external | "
        "export_elapsed_ms_p50 | export_elapsed_ms_p95 | retry_overhead_ms | result_exists_rate | result_nonzero_bytes_rate |"
    )
    lines.append(
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    )

    for dataset in dataset_order:
        data = payload[dataset]
        attempts = data["merge_attempts"]
        success = data["merge_success"]
        fail_export = data["merge_fail_export_failed"]
        fail_force = data["merge_fail_force_stop_external"]
        p50 = percentile(data["success_elapsed_ms"], 50)
        p95 = percentile(data["success_elapsed_ms"], 95)
        overhead = (
            sum(data["retry_overheads"]) / len(data["retry_overheads"]) if data["retry_overheads"] else 0
        )
        exists_rate = format_rate(data["result_exists"], success)
        nonzero_rate = format_rate(data["result_nonzero_bytes"], success)

        overall["merge_attempts"] += attempts
        overall["merge_success"] += success
        overall["merge_fail_export_failed"] += fail_export
        overall["merge_fail_force_stop_external"] += fail_force
        overall["success_elapsed_ms"].extend(data["success_elapsed_ms"])
        overall["retry_overheads"].extend(data["retry_overheads"])
        overall["result_exists"] += data["result_exists"]
        overall["result_nonzero_bytes"] += data["result_nonzero_bytes"]

        p50_txt = f"{int(p50)}" if p50 is not None else "-"
        p95_txt = f"{int(p95)}" if p95 is not None else "-"
        overhead_txt = f"{int(overhead)}" if data["retry_overheads"] else "-"

        lines.append(
            f"| {dataset} | {attempts} | {success} | {fail_export} | {fail_force} | "
            f"{p50_txt} | {p95_txt} | {overhead_txt} | {exists_rate:.2f}% | {nonzero_rate:.2f}% |"
        )

    overall_p50 = percentile(overall["success_elapsed_ms"], 50)
    overall_p95 = percentile(overall["success_elapsed_ms"], 95)
    overall_overhead = (
        sum(overall["retry_overheads"]) / len(overall["retry_overheads"]) if overall["retry_overheads"] else 0
    )
    overall_exists = format_rate(overall["result_exists"], overall["merge_success"])
    overall_nonzero = format_rate(overall["result_nonzero_bytes"], overall["merge_success"])

    lines.extend([
        "",
        "## Overall Summary",
        "",
        "| KPI | Value |",
        "|---|---:|",
        f"| merge_attempts | {overall['merge_attempts']} |",
        f"| merge_success | {overall['merge_success']} |",
        f"| merge_fail_export_failed | {overall['merge_fail_export_failed']} |",
        f"| merge_fail_force_stop_external | {overall['merge_fail_force_stop_external']} |",
        f"| export_elapsed_ms_p50 | {int(overall_p50) if overall_p50 is not None else '-'} |",
        f"| export_elapsed_ms_p95 | {int(overall_p95) if overall_p95 is not None else '-'} |",
        f"| retry_overhead_ms | {int(overall_overhead) if overall['retry_overheads'] else '-'} |",
        f"| result_exists_rate | {overall_exists:.2f}% |",
        f"| result_nonzero_bytes_rate | {overall_nonzero:.2f}% |",
    ])

    return "\n".join(lines) + "\n"


def aggregate_states(states: dict[str, dict]) -> dict[str, dict]:
    by_dataset: dict[str, dict] = defaultdict(lambda: {
        "merge_attempts": 0,
        "merge_success": 0,
        "merge_fail_export_failed": 0,
        "merge_fail_force_stop_external": 0,
        "success_elapsed_ms": [],
        "retry_overheads": [],
        "result_exists": 0,
        "result_nonzero_bytes": 0,
    })

    for state in states.values():
        dataset = state.get("dataset", "unassigned")
        attempts = state.get("attempts", {})
        if not attempts:
            continue

        data = by_dataset[str(dataset)]
        data["merge_attempts"] += len(attempts)

        final_attempt_no = max(attempts)
        final = attempts.get(final_attempt_no, {})
        final_status = final.get("status")
        final_external = bool(final.get("is_external_force_stop", False))

        if final_status == "success":
            data["merge_success"] += 1
            elapsed = to_int(final.get("elapsed_ms"))
            if elapsed is not None:
                data["success_elapsed_ms"].append(elapsed)

            result_exists = final.get("resultExists")
            result_bytes = final.get("resultBytes")
            if result_exists:
                data["result_exists"] += 1
            if isinstance(result_bytes, int) and result_bytes > 0:
                data["result_nonzero_bytes"] += 1
        else:
            if final_external:
                data["merge_fail_force_stop_external"] += 1
            else:
                # merge fail로 집계될 수 있는 실패 케이스(외부 force-stop 아님)
                data["merge_fail_export_failed"] += 1

        if 1 in attempts and 2 in attempts:
            t1 = to_int(attempts[1].get("elapsed_ms"))
            t2 = to_int(attempts[2].get("elapsed_ms"))
            if t1 is not None and t2 is not None:
                overhead = max(0, t2 - t1)
                if overhead >= 0:
                    data["retry_overheads"].append(overhead)

    return by_dataset


def main() -> int:
    args = parse_args()
    args.log_dir.mkdir(parents=True, exist_ok=True)

    run_by_run_id, run_by_trace_id = read_schedule(args.schedule)

    states, matched_count, _ = collect_runs(
        args.log_dir,
        args.pattern,
        schedule_run_by_run_id=run_by_run_id,
        schedule_run_by_trace_id=run_by_trace_id,
        include_unassigned=args.include_unassigned,
    )
    aggregated = aggregate_states(states)

    report = build_markdown(aggregated, matched_count)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        f.write(report)

    print(f"[Report] generated: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
