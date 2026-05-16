# LatencyBench

LatencyBench is a small iOS app for measuring Core ML inference latency on a
real iPhone. It runs a local HTTP server on the phone, accepts a `.mlmodel`
upload from a laptop, compiles the model on-device, runs warmup and timed
predictions, and returns latency statistics as JSON.

This is useful when you need repeatable device-side measurements while iterating
on model architectures, conversion settings, or Core ML compute-unit choices.

## What It Measures

LatencyBench measures the wall-clock time for repeated calls to:

```swift
model.prediction(from: input)
```

The current input generator is intentionally simple: it finds the model's first
input, requires that input to be an `MLMultiArray`, creates a zero-filled array
with the model's declared shape and data type, and reuses that input for all
warmup and timed runs.

This makes the app a generic Core ML forward-pass latency harness for compatible
models. It is not an end-to-end task benchmark unless your task latency is well
represented by a single zero-input Core ML prediction.

## API

When the app is running on the iPhone, it displays a URL like:

```text
http://192.168.1.42:8765
```

### Health Check

```bash
curl http://IPHONE_IP:8765/health
```

Returns:

```json
{
  "device": "iPhone",
  "status": "ok",
  "system": "iOS 17.0"
}
```

### Benchmark A Model

```bash
curl -X POST \
  --data-binary @MyModel.mlmodel \
  "http://IPHONE_IP:8765/benchmark?model_id=my_model&warmup=10&runs=50&compute_units=all"
```

Query parameters:

| Parameter | Default | Description |
| --- | --- | --- |
| `model_id` | `uploaded_model` | Name used when storing the uploaded model. Unsafe filename characters are replaced with `_`. |
| `warmup` | `10` | Number of untimed predictions before measurement. |
| `runs` | `50` | Number of timed predictions. |
| `compute_units` | `all` | One of `all`, `cpuOnly`, `cpuAndGPU`, or `cpuAndNeuralEngine`. |

Returns:

```json
{
  "model_id": "my_model",
  "compute_units": "all",
  "warmup": 10,
  "runs": 50,
  "median_ms": 1.23,
  "mean_ms": 1.31,
  "std_ms": 0.08,
  "p90_ms": 1.44,
  "p95_ms": 1.50,
  "min_ms": 1.12,
  "max_ms": 1.62,
  "latencies_ms": [1.21, 1.24]
}
```

You can also use the included Python helper:

```bash
python3 scripts/benchmark_model.py \
  --url http://IPHONE_IP:8765 \
  --model MyModel.mlmodel \
  --model-id my_model \
  --warmup 10 \
  --runs 50 \
  --compute-units all
```

## Build And Run

The project uses XcodeGen to keep the checked-in project definition small.

```bash
brew install xcodegen
xcodegen generate
open LatencyBench.xcodeproj
```

In Xcode:

1. Set a development team if needed.
2. Select a physical iPhone target.
3. Build and run the app.
4. Keep the app open while benchmarking.

The first request from your laptop may trigger Apple's local network permission
prompt on the phone. Allow access so the laptop can reach the server.

## Compatibility

Works well for:

- Core ML models with an `MLMultiArray` first input.
- Model-forward latency comparisons.
- Measuring different Core ML compute-unit settings.
- Research loops that repeatedly convert and test candidate architectures.

Current limitations:

- Only the first model input is used.
- The input must be an `MLMultiArray`.
- Input values are always zeros.
- Image, text, sequence, recurrent-state, and multi-input models need additional
  input generation logic.
- The server has no authentication and should only be used on a trusted local
  network.

## Project Layout

```text
LatencyBench/
  BenchmarkServer.swift     HTTP server and request parsing
  LatencyBenchApp.swift     SwiftUI app shell
  ModelBenchmarker.swift    Core ML compile/load/run logic
  Info.plist                iOS app permissions and metadata
scripts/
  benchmark_model.py        Minimal laptop-side upload client
project.yml                 XcodeGen project definition
```

## Notes For Reuse

If you want to use this across research projects, the most useful extension
points are:

- Add input generators for image, text, multiple-input, or recurrent models.
- Add metadata to benchmark requests so results can be tied back to experiment
  configs.
- Save benchmark results on the laptop side with model hash, iPhone model, iOS
  version, compute units, and conversion settings.
- Add a dedicated client package if you start using this from many repositories.
