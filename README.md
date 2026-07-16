# 🧠 CardioGuard AI: Pruning & Quantization Case Study

> This started as a BLE-integration technical challenge (Scenario + Technical
> Requirements below) and was later extended into a practical case study applying
> concepts from my postgraduate studies in Artificial Intelligence & Machine
> Learning (PUC): an **on-device AI early-warning model** - PyTorch → structured
> pruning → quantization (PTQ) → Core ML → Swift integration, plus a
> local-first/cloud-fallback composition (`HybridCardioRiskPredictor`) - sitting
> alongside the original clinical rule engine. Jump to
> [🧠 On-Device AI](#-on-device-ai-predictive-early-warning) or the
> [pipeline README](./MLPipeline/README.md) for that part.
>
> **Scope, by choice:** this is iOS-only (Swift/SwiftUI/Core ML). Extending the
> same model to Android (Kotlin + TensorFlow Lite/ONNX Runtime) is a real,
> separate undertaking - a different runtime, a different conversion path from
> the same PyTorch model, a different UI stack - not something to bolt onto this
> repo as an afterthought. It's left out deliberately rather than half-done here.

## 🩺 The Scenario
The company is prototyping a domestic and continuous cardiovascular monitor. This BLE (Bluetooth Low Energy) device transmits in real-time two critical pieces of user data: **Heart Rate (BPM)** and **Systolic/Diastolic Blood Pressure (mmHg)**.

The purpose of your app is to connect to this monitor, process data asynchronously and securely, and alert the user immediately if there is a dangerous variation (such as a peak in hypertension or a severe drop in pressure/bradycardia).

---
> 💡 **Project Purpose:** This project was developed exclusively as a hands-on study to master **Bluetooth Low Energy (BLE)** integration in iOS, focusing on Swift 6 Structured Concurrency, data safety, and robust byte parsing for connected devices.

---
## 🛠 Technical Requirements

### 1. Connectivity & Data Parsing Layer (Swift 6)
Instead of generic data, your `CoreBluetooth` byte parser should decode structured health data.
* **Structured Concurrency:** Use Swift 6 `AsyncStream` to receive the continuous flow of data from the peripheral.
* **Payload Simulation (Bytes):** The device firmware sends packets containing beats and pressure. In your test/mock code, you must process byte arrays.
    * **Package schema:** `[BPM, Systolic Pressure, Diastolic Pressure]`
    * **Example payload:** `[0x4B, 0x78, 0x50]` $\rightarrow$ Decoded as **75 BPM, 120/80 mmHg** (Normal pressure).

### 2. Business Rules & Alerting (UI in SwiftUI)
The core strength of this test is the logic used to identify cardiovascular risks. The UI must react instantly to these states using `@MainActor`:
* **Crisis State (Red Visual Alert):**
    * **High Blood Pressure (Hypertension):** Systolic $> 140$ mmHg OR Diastolic $> 90$ mmHg.
    * **Low Blood Pressure (Hypotension):** Systolic $< 90$ mmHg.
    * **Cardiac Anomaly:** BPM $> 120$ (Tachycardia at rest) OR BPM $< 50$ (Bradycardia).
* **Main Dashboard:**
    * Simple chart or clear numerical indicators of current pressure and recent history.
    * Connection status with the heart monitor.

### 3. Symptom-Based Unit Tests (TDD)
Since we are dealing with sensitive health data, your unit tests (using `XCTest` or `Quick`/`Nimble`) need to be extremely rigorous:
* **Test Case 1:** Validate if the `ViewModel` triggers the *"Hypotension Alert"* state when the BLE mock sends a systolic pressure of `85 mmHg`.
* **Test Case 2:** Ensure that the parser does not crash and handles errors cleanly if the peripheral sends a corrupted or incomplete byte package.

### 4. Memory and Concurrency Management
* **Stream Lifecycle:** Ensure that the data flow (`AsyncStream`) is cancelled correctly when the user leaves the dashboard screen, preventing memory leaks and unnecessary background processing.

---

## 🧠 On-Device AI: Predictive Early Warning

The original technical challenge above is a reactive system: `EvaluateCardioRiskUseCase`
flags a crisis the instant a single reading crosses a hard clinical threshold. That's
correct and necessary, but it's structurally reactive - it can't warn the user
*before* the threshold is crossed.

`CardioRiskPredictor` extends the app with a small on-device model that looks at the
**trend** across the last 6 BLE readings and predicts the probability of a crisis in
the next 3 readings - catching gradual deterioration the rule engine can't see by
design. The two run side by side in `DashboardViewModel`: the rule engine gives
instant, explainable, zero-latency ground truth (`alertState`); the model gives an
earlier, probabilistic signal (`aiRiskPrediction`), surfaced as its own "AI Trend
Analysis" card in the dashboard.

**Pipeline:** synthetic patient-trajectory dataset → PyTorch MLP (18 → 16 → 8 → 1) →
structured neuron pruning (57% of parameters removed, no accuracy/F1 regression) →
Core ML (`.mlpackage`) conversion → loaded on-device via `CoreMLCardioRiskPredictor`
(`Data/MLModel/`), behind the `CardioRiskPredicting` protocol
(`Domain/Protocols/`) so `DashboardViewModel` never imports CoreML directly.

Full pipeline, methodology, and validated results (accuracy/precision/recall/F1
before and after pruning, broken down by scenario) are in
[`MLPipeline/README.md`](./MLPipeline/README.md) - including an explicit note on how
it was built and validated in an offline sandbox with no package-registry access.

> ⚠️ **Working in `MLPipeline/` locally:** `pip install -r requirements.txt`
> creates a `.venv/` with `torch` + `coremltools`, which pulls in a 300MB+
> `libtorch_cpu.dylib` - it's already covered by `MLPipeline/.gitignore`, but
> if you ever commit from the repo root with a broad `git add .`, check
> `git status` first. GitHub hard-rejects any pushed file over 100MB, and
> once a virtualenv like this lands in a commit, deleting it in a *later*
> commit doesn't fix the push - the oversized blob is still part of the
> earlier commit's history being sent. The only fix is rewriting the commit
> that introduced it (`git commit --amend`, safe only if that commit was
> never pushed).

**Design decisions worth calling out:**
* Normalization is baked into the PyTorch model (registered buffers), so the exported
  Core ML model accepts raw vitals directly - no preprocessing duplicated in Swift.
* Pruning is **structured** (whole neurons removed, not individual weights zeroed),
  because unstructured sparsity doesn't shrink a dense matrix or reduce Core ML
  inference latency unless the runtime has sparse-kernel support.
* On top of pruning, `MLPipeline/quantize.py` applies **Post-Training Quantization**
  (float16 via Core ML's native compute precision, then int8 weight-only via
  `coremltools.optimize.coreml`) - both validated as accuracy-neutral on the
  synthetic dataset (see `MLPipeline/README.md`'s "Quantization (PTQ)" section).
* `CoreMLCardioRiskPredictor` loads the model by name via the generic `MLModel` API
  rather than Xcode's auto-generated model class, so the app compiles and runs even
  before a `.mlpackage` is bundled (predictions just become unavailable, and the AI
  card stays hidden) - see `CardioGuard/Resources/MLModels/README.md`.
* `AppContainer` wraps `CoreMLCardioRiskPredictor` in a `HybridCardioRiskPredictor`
  alongside a `RemoteCardioRiskPredictor` - a **local-first, cloud-fallback**
  strategy: the on-device model is always tried first, and the cloud path is only
  consulted if it throws. `AIRiskPrediction.source` (`.onDevice`/`.cloud`) is
  surfaced all the way to the dashboard's "AI Trend Analysis" card, so which path
  actually answered is never hidden from the user. No real backend is deployed
  (`CloudInferenceConfig.endpoint` is `nil` by default) - honestly, standing up cloud
  inference infrastructure is out of scope for a demo app, so this ships as a real,
  tested composition pattern with an inert remote leg, not a working cloud service.
* `EvaluateCardioRiskUseCase` and `CardioRiskPredicting` both default-construct in
  `DashboardViewModel.init`, so the existing BLE/threshold test suite keeps compiling
  unchanged while `AppContainer` wires the real Core ML implementation for the app.

---

## 🏗️ Architecture Deep-Dive

### The iOS app: a small Clean Architecture, top to bottom

```
CardioGuard/
  App/            CardioGuardApp.swift - @main entry point
  Core/           DI container (AppContainer, RunEnvironment), design tokens (AppTheme)
  Domain/         Entities, protocols, use cases - zero framework imports (no SwiftUI/CoreBluetooth/CoreML)
  Data/           Concrete implementations of Domain protocols - BLE (CoreBluetooth) and ML (Core ML)
  Presentation/   SwiftUI Views + @Observable ViewModels (MVVM), one folder per feature
  Resources/      MLModels/CardioRiskPredictor.mlpackage (see below)
```

The dependency rule is enforced by protocol placement, not by module boundaries (it's a
single app target, not separate Swift packages): every protocol lives in `Domain/Protocols/`,
every concrete side-effecting implementation lives in `Data/`, and `Presentation/` only ever
talks to the `Domain/` protocol types. `Core/DependencyInjection/AppContainer.swift` is the
single composition root - the only place that imports both a `Domain` protocol and its
`Data` implementation and wires them together:

```swift
func makeCardioMonitorService() -> CardioMonitorServing {
    switch runEnvironment {
    case .simulated: return SimulatedCardioMonitorService()
    case .live: return BLECardioMonitorRepository(central: centralManager)
    }
}
```

`runEnvironment` is an injectable `RunEnvironment` (`.simulated`/`.live`, defaulting to
`.current`, which reads `#if targetEnvironment(simulator)` internally) rather than a
compile-time branch inline at the call site - see "Trade-offs" below for why.

**The life of one reading**, end to end:

1. `BLECentralManager` (a `CBCentralManagerDelegate`/`CBPeripheralDelegate`, running its
   callbacks on a background `DispatchQueue`) receives a 3-byte characteristic update and
   hands the raw bytes to `BLEDataParser`.
2. `BLEDataParser.parse(payload:)` decodes `[BPM, Systolic, Diastolic]` into a
   `CardioVascularMetrics` value, or throws `.invalidPacketLength` if the packet isn't
   exactly 3 bytes.
3. The decoded value is `yield`-ed into an `AsyncStream<CardioVascularMetrics>` continuation
   - this is the concurrency seam: CoreBluetooth's callback world hands off to Swift
     structured concurrency here, and `AsyncStream.Continuation.yield` is safe to call from
     any thread, so no manual locking is needed crossing from the background BLE queue.
4. `BLECardioMonitorRepository` (implementing `CardioMonitorServing`, the Domain-facing
   protocol) just forwards that stream from `BLECentralManaging` - it exists purely to keep
   `DashboardViewModel` from depending on a CoreBluetooth-shaped type at all.
5. `DashboardViewModel.start()` runs `for await metrics in monitorService.metricsStream`
   inside a `Task`, on the `@MainActor` the class is annotated with - this is where the
   background-thread-to-UI hand-off actually completes.
6. Each reading is evaluated **twice, independently**: `EvaluateCardioRiskUseCase.primaryAlert(for:)`
   (instant, deterministic, a strategy-pattern aggregation of `BPMClinicalThresholds` /
   `SystolicClinicalThresholds` / `DiastolicClinicalThresholds`, each conforming to
   `EvaluateCardioRiskUseCaseStrategy`) updates `alertState` synchronously; and the reading is
   appended to a `ReadingWindow` (a small rolling-buffer type of its own) that, once full, is
   handed off to `CardioRiskPredicting.predict(window:)` (the Core ML model) to update
   `aiRiskPrediction` asynchronously.
7. `DashBoardUIView`, an `@Observable`-driven SwiftUI view, renders both outputs as two
   visually distinct cards (`alertBanner` for the instant rule engine, `aiRiskCard` for the
   predictive model) - so the user never sees them conflated into one signal.

**Testing strategy:** every side-effecting dependency is a protocol with a small,
hand-rolled test double - no mocking framework. `BLECardioMonitorMock` (living in
`CardioGuardTests/`, not shipped in the app target) substitutes for `CardioMonitorServing`
(with `emit(_:)` to push readings and call counters to assert on), `CardioRiskPredictorMock`
substitutes for `CardioRiskPredicting` (stubbed prediction or error) - and
`HybridCardioRiskPredictorTests` reuses two independent instances of that same mock (one as
`local`, one as `remote`) to verify the fallback contract: local-succeeds never touches
remote, local-fails calls remote and tags the result `.cloud`, both-fail propagates remote's
error. All test files (`CardioGuardTests`, `DashboardViewModelTests`, `CardioAIPredictionTests`,
`HybridCardioRiskPredictorTests`, plus the parser tests) use Swift Testing (`@Suite`/`@Test`,
`#expect`, tagged `.success`/`.failure` via `Tag+Extension.swift`) rather than XCTest.
`EvaluateCardioRiskUseCaseTests` (in `CardioGuardTests`) owns the exhaustive per-threshold +
boundary-value matrix (e.g. "BPM exactly 50 does NOT trigger bradycardia");
`DashboardViewModelTests` only re-checks that matrix's result actually reaches `alertState`
through the ViewModel, rather than repeating every boundary a second time.

### MLPipeline: an independent, offline-first training pipeline

`MLPipeline/` is deliberately **not** part of the Xcode project or Swift build graph - it's
a standalone Python tool whose only interface to the app is the artifact it produces
(`CardioRiskPredictor.mlpackage`) plus a small set of conventions that must be kept in sync
by hand: input name `"readings"` / shape `[1,6,3]`, output name `"risk_score"` / shape
`[1,1]`, and a window size of 6 (`CardioRiskPredictorConfig.windowSize` in Swift mirrors
`WINDOW_SIZE` in `generate_data.py`). This is intentional - the ML side can be rerun,
retrained, or re-architected entirely independently of the app, at the cost of nothing
enforcing that contract at compile time (more on that below).

Two design choices carry across the Swift/Python boundary on purpose:
* **Normalization lives in the model, not the client.** `CardioRiskNet` registers `mean`/
  `std` as buffers and applies them inside `forward()`, so the exported Core ML model
  accepts raw vitals directly - there's exactly one place scaling logic exists, and it's
  not Swift.
* **Pruning is structural**, not sparse. Whole neurons (16→8, then 8→4) are removed by L2
  norm of outgoing weights, because Core ML's default compute path doesn't get any benefit
  from unstructured (weight-level) sparsity - only an actual smaller matrix helps at
  inference time.

`reference_validation/` is a from-scratch NumPy reimplementation of the same dataset,
architecture, and pruning strategy, written and run when the sandbox this pipeline was
authored in had no internet access to install `torch`/`coremltools`. It's kept around as an
independent second implementation to sanity-check the real PyTorch/Core ML numbers against
(see `MLPipeline/README.md`), not as the source of truth anymore.

### Where the two worlds meet

`CardioGuard/Resources/MLModels/CardioRiskPredictor.mlpackage` is picked up automatically by
Xcode 16's synchronized groups - no `.pbxproj` editing. `CoreMLCardioRiskPredictor` loads it
through the generic `MLModel` API by string name (rather than the class Xcode can
auto-generate from the `.mlpackage`), specifically so the Swift target **compiles and runs
even if `MLPipeline/` was never run** - if the file is missing, `model` is `nil`,
`predict(window:)` throws `.modelUnavailable`, and `DashboardViewModel`'s
`try? await aiPredictor.predict(...)` just leaves `aiRiskPrediction` as `nil`, so the AI card
stays hidden instead of the app crashing.

### Trade-offs and honest limitations

**iOS side - resolved:** an earlier pass through this section flagged nine concrete gaps;
all nine have since been addressed directly in the code, not just written up:

* Mock-vs-real is no longer an inline `#if targetEnvironment(simulator)` at the call site -
  `AppContainer` now takes an injectable `RunEnvironment` (`Core/DependencyInjection/RunEnvironment.swift`,
  defaulting to `.current`), so the choice is explicit and overridable instead of a compile-time
  branch baked into the composition root.
* The Simulator fallback and the test double are no longer the same type. Production code
  now uses `SimulatedCardioMonitorService` (`Data/BLE/Central/`, no test instrumentation,
  never shipped-with-test-surface); `BLECardioMonitorMock` (with `emit()` and the call-count
  spies) moved into `CardioGuardTests/` and is a test-only type now.
* `AppContainer.makeScannerViewModel()` is no longer dead code - `ScannerUIView` constructs
  its ViewModel through it, matching `DashBoardUIView`'s pattern. The unused `AppRouter`/`AppScreen`
  navigation stack was deleted outright (Dashboard→Scanner is still a plain `.sheet`, which is
  the right tool for a modal picker - there was no real push-navigation need to justify keeping
  the router around).
* Scanner is wired to real BLE discovery end to end: a new `BLEDeviceScanning` protocol
  (`Domain/Protocols/`) is implemented by `BLEDeviceScannerRepository` for real devices and
  `SimulatedBLEDeviceScanner` for the Simulator; `BLECentralManager` now yields every
  discovered peripheral as a `DiscoveredDevice` (instead of silently auto-connecting to the
  first one found) and exposes an explicit `connect(to:)` that suspends until CoreBluetooth
  confirms the connection and notification subscription. `AppContainer` shares one
  `BLECentralManager` instance between the monitor service and the device scanner in the
  `.live` case, so a device picked in the Scanner is the same CoreBluetooth session
  `DashboardViewModel` reads its `metricsStream` from - not two disconnected code paths
  anymore. **Behavior change worth flagging:** on a real device, "Start Monitoring" no longer
  silently auto-connects to the first heart-rate peripheral found; you now pick the device via
  the Scanner first. That's arguably better product behavior (no silent connection to a random
  nearby device), but it is a real change from the previous implicit auto-connect.
* `BLEDataParser`'s `corruptedData` guard now does real work - it checks each vital against a
  physiologically-plausible range (`PlausibleRange` in `BLEDataParser.swift`: BPM/Systolic
  0–250, Diastolic 0–200) instead of a `>= 0` check that could never fail given `UInt8` input.
* `BLECentralManager` now carries an explicit header comment stating it is *not* GATT-compliant
  (the real Heart Rate Measurement characteristic doesn't carry blood pressure at all) - this
  was a documentation gap, not a functional one, and rewriting the parsing to be truly
  GATT-compliant is out of scope for what this project simulates.
* `DashBoardUIView` and `ScannerUIView` now consume `AppTheme.Colors`/`Radius`/`Spacing`/`Animation`
  throughout instead of hardcoding the equivalent literals (two small tokens, `Colors.bradycardia`
  and `Spacing.snug`, were added to cover values the views already used that had no matching
  token yet).
* The rolling AI-prediction window moved out of `DashboardViewModel` into its own
  `ReadingWindow` type (`Domain/UseCases/ReadingWindow.swift`) - the ViewModel now just calls
  `readingWindow.appending(metrics)` and reacts to the result, instead of owning the
  append/trim/count-check bookkeeping inline.
* The naming/formatting rough edges are fixed: the parser file lost its leading space
  (`BLEDataParser.swift`), `Core/DependecyInjection` is now `Core/DependencyInjection`,
  `CardioVascularMetrics.SystoliC` is now `Systolic`, its computed formatted-string property
  is now `formattedTimestamp` (no longer a near-collision with the stored `Timestamp`), and
  `EvaluateCardioRiskUseSG` is now `EvaluateCardioRiskUseCaseStrategy`.
* `DashboardViewModelTests`' boundary-value matrix was trimmed down to two representative
  wiring tests (`riskyReadingUpdatesAlertState`, `normalReadingKeepsAlertStateNormal`); the
  exhaustive per-threshold/boundary-value matrix now lives only in
  `EvaluateCardioRiskUseCaseTests`, so a future threshold change only needs updating in one place.

**ML side:**
* The Swift↔Python contract (`"readings"` / `"risk_score"` / `[1,6,3]` / window size 6) is
  enforced only by comments and convention, not by any generated interface or CI check. A
  future retrain that changes an output name or shape in `prune_and_convert.py` would fail
  silently at *runtime* (`predict()` throws, the AI card just stays hidden) rather than at
  build time. A lightweight CI step that loads the `.mlpackage` spec and asserts the
  expected input/output names and shapes would close that gap cheaply.
* The pruned `.mlpackage` is only ~11% smaller on disk than the baseline despite 57% fewer
  parameters - at a few hundred parameters, the fixed `mlprogram` container format
  overhead dominates the file, so pruning's on-disk win is close to nil at this scale. The
  real payoff, if any, would show up as inference latency on a real device, which hasn't
  been measured yet - worth profiling with Xcode's Core ML Performance Report before
  claiming a performance win from pruning (see the latency note in `MLPipeline/README.md`).
* There's no automated path from `MLPipeline/` to the bundled `.mlpackage` - it's a manual
  "run two scripts, drag the file into Xcode" step, so the bundled model can silently drift
  from what the pipeline would currently produce if either side changes. A script or CI job
  that regenerates and diffs the bundled model would remove that as a source of error.
