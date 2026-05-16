# AGENTS.md

Guidance for coding agents working in this repository.

## Repository Purpose

LatencyBench is a small iOS benchmarking app for measuring Core ML inference
latency on a physical iPhone. The app starts a local HTTP server, accepts a
`.mlmodel` upload, compiles it on-device, runs warmup and timed predictions, and
returns JSON latency statistics.

This repo is intentionally lightweight. Prefer small, explicit changes over new
frameworks or broad refactors.

## Project Layout

```text
LatencyBench/
  BenchmarkServer.swift     TCP HTTP server, request parsing, JSON responses
  LatencyBenchApp.swift     SwiftUI app shell and displayed server status
  ModelBenchmarker.swift    Core ML compile/load/input/timing logic
  Info.plist                iOS permissions and app metadata
scripts/
  benchmark_model.py        Laptop-side upload client
project.yml                 XcodeGen project definition
LatencyBench.xcodeproj/     Generated Xcode project
README.md                   User-facing usage documentation
```

## Tooling

- The canonical project definition is `project.yml`.
- Regenerate the Xcode project after changing target settings:

```bash
xcodegen generate
```

- Build from the command line when possible:

```bash
xcodebuild -project LatencyBench.xcodeproj -scheme LatencyBench -destination 'generic/platform=iOS' build
```

- Run on a physical iPhone from Xcode for real benchmarking. Simulator results
  are not useful for Core ML latency comparisons.

## App Architecture

- `LatencyBenchApp.swift` creates one `BenchmarkServer(port: 8765)` and shows
  status, URL, and last result in a minimal SwiftUI view.
- `BenchmarkServer.swift` uses `Network.NWListener` and `NWConnection` directly.
  It implements only the small HTTP subset needed by `/health` and
  `/benchmark`.
- `ModelBenchmarker.swift` owns model upload, Core ML compilation, model load,
  zero-filled `MLMultiArray` input generation, warmup, timed prediction, and
  summary statistics.
- `scripts/benchmark_model.py` is dependency-free Python and should stay usable
  from a normal system Python.

## Behavioral Contracts

Keep these API surfaces stable unless the README and client script are updated
in the same change:

- `GET /health`
- `POST /benchmark?model_id=...&warmup=...&runs=...&compute_units=...`
- Supported `compute_units`: `all`, `cpuOnly`, `cpuAndGPU`,
  `cpuAndNeuralEngine`
- JSON result keys from `BenchmarkResult`, especially `latencies_ms` and the
  aggregate millisecond metrics.

The benchmark currently supports models whose first input is an `MLMultiArray`.
If adding image, text, sequence, multi-input, or recurrent-state support, keep
the existing simple `MLMultiArray` path working.

## Swift Style

- Match the existing direct Swift style. Avoid unnecessary abstractions.
- Use `Foundation`, `Network`, `CoreML`, `SwiftUI`, and `UIKit` APIs directly
  unless there is a clear reason to add a dependency.
- Keep UI state updates on the main queue.
- Be careful with request parsing and file writes because the HTTP server runs
  inside the app process.
- Preserve the trusted-local-network assumption. Do not expose this as a
  general-purpose authenticated server without explicitly designing that change.
- Prefer clear `NSError` messages for benchmark failures because they are
  returned to the laptop client and shown in the app.

## Benchmarking Notes

- Real latency numbers require a physical iPhone with the app open.
- The first laptop request may trigger the iOS local network permission prompt.
- Uploaded models are written under the app documents directory in
  `LatencyBench/Uploaded`; compiled models are copied to
  `LatencyBench/Compiled`.
- Timings measure only repeated calls to:

```swift
model.prediction(from: input)
```

- Do not interpret the default zero-input benchmark as end-to-end task latency.

## Python Client Notes

- Keep `scripts/benchmark_model.py` standard-library-only unless there is a
  strong reason to add packaging.
- Preserve nonzero exit codes for missing model files, HTTP errors, and request
  failures.
- If adding result persistence, include enough metadata to reproduce comparisons:
  model id or hash, device, iOS version, compute units, warmup, runs, and
  conversion settings when available.

## Documentation

Update `README.md` whenever changing:

- API endpoints or query parameters
- JSON response fields
- supported model input types
- compute unit behavior
- build/run instructions
- benchmark interpretation or limitations

## Safety For Future Agents

- Do not discard local changes you did not make.
- Do not edit generated Xcode project files by hand when the same change belongs
  in `project.yml`; regenerate the project instead.
- Keep changes scoped. This repo is a benchmarking harness, not a full app
  platform.
- If a change can affect latency measurements, document the measurement impact
  and prefer validating on-device.
