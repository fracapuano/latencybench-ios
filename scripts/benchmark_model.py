#!/usr/bin/env python3
"""Upload a Core ML model to a running LatencyBench iPhone app."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Benchmark a .mlmodel file with the LatencyBench iPhone app."
    )
    parser.add_argument(
        "--url",
        required=True,
        help="Base app URL shown on the iPhone, for example http://192.168.1.42:8765.",
    )
    parser.add_argument("--model", required=True, type=Path, help="Path to a .mlmodel file.")
    parser.add_argument("--model-id", default=None, help="Identifier to include in results.")
    parser.add_argument("--warmup", type=int, default=10, help="Number of warmup predictions.")
    parser.add_argument("--runs", type=int, default=50, help="Number of timed predictions.")
    parser.add_argument(
        "--compute-units",
        default="all",
        choices=["all", "cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine"],
        help="Core ML compute units to request.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the JSON response.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    model_path = args.model
    if not model_path.is_file():
        print(f"Model file not found: {model_path}", file=sys.stderr)
        return 2

    model_id = args.model_id or model_path.stem
    query = urllib.parse.urlencode(
        {
            "model_id": model_id,
            "warmup": args.warmup,
            "runs": args.runs,
            "compute_units": args.compute_units,
        }
    )
    base_url = args.url.rstrip("/")
    endpoint = f"{base_url}/benchmark?{query}"

    request = urllib.request.Request(
        endpoint,
        data=model_path.read_bytes(),
        method="POST",
        headers={"Content-Type": "application/octet-stream"},
    )

    try:
        with urllib.request.urlopen(request, timeout=None) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        print(f"HTTP {error.code}: {body}", file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f"Request failed: {error}", file=sys.stderr)
        return 1

    if args.pretty:
        parsed = json.loads(payload)
        print(json.dumps(parsed, indent=2, sort_keys=True))
    else:
        print(payload.decode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
