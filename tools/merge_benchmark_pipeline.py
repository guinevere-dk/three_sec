#!/usr/bin/env python3
"""Phase 3 병합 벤치마크 실행 파이프라인."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
import uuid


ROOT_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG = ROOT_DIR / "benchmark_runs.example.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Phase 3 merge benchmark pipeline",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="벤치마크 시나리오 JSON 파일 경로",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=Path("logs/benchmark"),
        help="실행 로그를 저장할 디렉터리",
    )
    parser.add_argument(
        "--runs-per-dataset",
        type=int,
        default=10,
        help="데이터셋당 실행 횟수",
    )
    parser.add_argument(
        "--command-template",
        type=str,
        default="",
        help=(
            "벤치마크 실행 명령 템플릿. 예: "
            '"'"'python scripts/run_one_benchmark.py --dataset {dataset_id} --run-id {run_id} --log {run_log_file}'"'"'
        ),
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("benchmark/merge_benchmark_v1.md"),
        help="리포트 출력 경로",
    )
    parser.add_argument(
        "--plan-only",
        action="store_true",
        help="실행하지 않고 실행 계획(JSON)만 생성",
    )
    parser.add_argument(
        "--skip-report",
        action="store_true",
        help="실행 후 리포트 생성을 생략",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="실패가 발생하면 즉시 종료",
    )
    return parser.parse_args()


def load_config(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"설정 파일을 찾을 수 없습니다: {path}")

    with path.open("r", encoding="utf-8") as f:
        payload = json.load(f)

    datasets = payload.get("datasets")
    if not isinstance(datasets, list) or not datasets:
        raise ValueError("datasets 항목이 비어 있습니다.")

    return payload


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def build_runs(config: dict, runs_per_dataset: int) -> list[dict]:
    plans: list[dict] = []
    for dataset in config["datasets"]:
        for idx in range(runs_per_dataset):
            plans.append(
                {
                    "run_id": uuid.uuid4().hex,
                    "trace_id": uuid.uuid4().hex[:16],
                    "dataset_id": dataset["id"],
                    "run_index": idx + 1,
                    "ab_group": dataset.get("ab_group", "A"),
                    "retry_plan": dataset.get("retry_plan", "default"),
                    "dataset_name": dataset.get("display_name", dataset["id"]),
                    "dataset_hint": dataset.get("dataset_hint", ""),
                }
            )
    return plans


def parse_placeholder_map(
    *,
    config: dict,
    run: dict,
    run_log: Path,
    log_dir: Path,
    runs_per_dataset: int,
) -> dict:
    dataset_id = run["dataset_id"]
    return {
        "dataset_id": dataset_id,
        "dataset_name": run["dataset_name"],
        "dataset_display_name": run["dataset_name"],
        "dataset_hint": run["dataset_hint"],
        "run_id": run["run_id"],
        "run_index": run["run_index"],
        "trace_id": run["trace_id"],
        "ab_group": run["ab_group"],
        "retry_plan": run["retry_plan"],
        "attempts_per_run": runs_per_dataset,
        "log_dir": str(log_dir),
        "run_log_file": str(run_log),
        "timestamp": datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        "command": config.get("default_command", ""),
        "dataset": dataset_id,
    }


def run_and_capture(command: str, run_log_path: Path) -> int:
    process = subprocess.run(
        command,
        cwd=ROOT_DIR,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    run_log_path.parent.mkdir(parents=True, exist_ok=True)
    with run_log_path.open("a", encoding="utf-8", errors="replace") as lf:
        if process.stdout:
            lf.write(process.stdout)
            if not process.stdout.endswith("\n"):
                lf.write("\n")
        lf.write(f"[Benchmark][Run] event=runner_end exit_code={process.returncode}\n")

    return process.returncode


def write_run_header(log_path: Path, run: dict) -> None:
    with log_path.open("w", encoding="utf-8", errors="replace") as lf:
        lf.write(
            f"[Benchmark][Run] event=run_start run_id={run['run_id']} "
            f"dataset={run['dataset_id']} run_index={run['run_index']}"
            f" traceId={run['trace_id']}\n"
        )
        lf.write(
            f"[Benchmark][Run] event=run_meta dataset={run['dataset_id']} "
            f"run_index={run['run_index']} abGroup={run['ab_group']} "
            f"retryPlan={run['retry_plan']} datasetHint={run['dataset_hint']}\n"
        )


def write_run_footer(log_path: Path, run: dict, exit_code: int) -> None:
    with log_path.open("a", encoding="utf-8", errors="replace") as lf:
        lf.write(
            f"[Benchmark][Run] event=run_end run_id={run['run_id']} "
            f"dataset={run['dataset_id']} run_index={run['run_index']} "
            f"traceId={run['trace_id']} exit_code={exit_code}\n"
        )


def call_reporter(log_dir: Path, schedule_path: Path, out_path: Path) -> int:
    report_script = ROOT_DIR / "merge_benchmark_report.py"
    command = (
        f'"{sys.executable}" "{report_script}" '
        f'--log-dir "{log_dir}" --schedule "{schedule_path}" --out "{out_path}"'
    )
    return subprocess.run(command, cwd=ROOT_DIR, shell=True).returncode


def main() -> int:
    args = parse_args()

    config = load_config(args.config)
    command_template = args.command_template.strip() or str(config.get("default_command_template", "")).strip()

    runs = build_runs(config, args.runs_per_dataset)
    now = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    args.log_dir.mkdir(parents=True, exist_ok=True)

    schedule = {
        "generated_at_utc": now,
        "runs_per_dataset": args.runs_per_dataset,
        "datasets": config["datasets"],
        "runs": runs,
    }

    schedule_path = args.log_dir / f"benchmark_runs_{now}.json"
    write_json(schedule_path, schedule)
    print(f"[Pipeline] schedule: {schedule_path}")

    if args.plan_only:
        print("[Pipeline] plan-only mode")
        if not args.skip_report:
            return call_reporter(args.log_dir, schedule_path, args.out)
        return 0

    for run in runs:
        run_log_path = args.log_dir / f"run_{run['dataset_id']}_{run['run_index']:02d}_{run['trace_id']}.log"
        write_run_header(run_log_path, run)

        with run_log_path.open("a", encoding="utf-8", errors="replace") as lf:
            lf.write(f"[Benchmark][Run] event=runner_start\n")

        exit_code = 0
        if command_template:
            context = parse_placeholder_map(
                config=config,
                run=run,
                run_log=run_log_path,
                log_dir=args.log_dir,
                runs_per_dataset=args.runs_per_dataset,
            )
            command = command_template.format(**context)
            with run_log_path.open("a", encoding="utf-8", errors="replace") as lf:
                lf.write(f"[Benchmark][Run] event=runner_command command={command}\n")
            exit_code = run_and_capture(command, run_log_path)
        else:
            with run_log_path.open("a", encoding="utf-8", errors="replace") as lf:
                lf.write("[Benchmark][Run] event=runner_skip reason=missing_command_template\n")

        write_run_footer(run_log_path, run, exit_code)
        if exit_code != 0 and args.fail_fast:
            print(f"[Pipeline] fail-fast enabled. stopped at run_id={run['run_id']}")
            return exit_code

    if args.skip_report:
        print(f"[Pipeline] complete ({len(runs)} runs), report skipped")
        return 0

    report_exit = call_reporter(args.log_dir, schedule_path, args.out)
    if report_exit != 0:
        print(f"[Pipeline] report generation failed: {report_exit}")
    else:
        print(f"[Pipeline] report generated: {args.out}")
    return report_exit


if __name__ == "__main__":
    raise SystemExit(main())
