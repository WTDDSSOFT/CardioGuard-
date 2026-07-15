# 📋 Technical Challenge: CardioGuard IoT Monitor

> This started as a BLE-integration challenge (Scenario + Technical Requirements
> below) and was later extended with an **on-device AI early-warning model** -
> PyTorch → structured pruning → Core ML → Swift integration - sitting alongside
> the original clinical rule engine. Jump to [🧠 On-Device AI](#-on-device-ai-predictive-early-warning)
> or the [pipeline README](./MLPipeline/README.md) for that part.

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
* `CoreMLCardioRiskPredictor` loads the model by name via the generic `MLModel` API
  rather than Xcode's auto-generated model class, so the app compiles and runs even
  before a `.mlpackage` is bundled (predictions just become unavailable, and the AI
  card stays hidden) - see `CardioGuard/Resources/MLModels/README.md`.
* `EvaluateCardioRiskUseCase` and `CardioRiskPredicting` both default-construct in
  `DashboardViewModel.init`, so the existing BLE/threshold test suite keeps compiling
  unchanged while `AppContainer` wires the real Core ML implementation for the app.

---

## 🏗️ Architecture Deep-Dive

### The iOS app: a small Clean Architecture, top to bottom

```
CardioGuard/
  App/            CardioGuardApp.swift - @main entry point, injects AppRouter into the environment
  Core/           DI container (AppContainer), navigation (AppRouter), design tokens (AppTheme)
  Domain/         Entities, protocols, use cases - zero framework imports (no SwiftUI/CoreBluetooth/CoreML)
  Data/           Concrete implementations of Domain protocols - BLE (CoreBluetooth) and ML (Core ML)
  Presentation/   SwiftUI Views + @Observable ViewModels (MVVM), one folder per feature
  Resources/      MLModels/CardioRiskPredictor.mlpackage (see below)
```

The dependency rule is enforced by protocol placement, not by module boundaries (it's a
single app target, not separate Swift packages): every protocol lives in `Domain/Protocols/`,
every concrete side-effecting implementation lives in `Data/`, and `Presentation/` only ever
talks to the `Domain/` protocol types. `Core/DependecyInjection/AppContainer.swift` is the
single composition root - the only place that imports both a `Domain` protocol and its
`Data` implementation and wires them together:

```swift
func makeCardioMonitorService() -> CardioMonitorServing {
    #if targetEnvironment(simulator)
    return BLECardioMonitorMock()
    #else
    return BLECardioMonitorRepository(central: BLECentralManager())
    #endif
}
```

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
   `EvaluateCardioRiskUseSG`) updates `alertState` synchronously; and the reading is pushed
   into a private rolling 6-reading window that, once full, is hived off to
   `CardioRiskPredicting.predict(window:)` (the Core ML model) to update `aiRiskPrediction`
   asynchronously.
7. `DashBoardUIView`, an `@Observable`-driven SwiftUI view, renders both outputs as two
   visually distinct cards (`alertBanner` for the instant rule engine, `aiRiskCard` for the
   predictive model) - so the user never sees them conflated into one signal.

**Testing strategy:** every side-effecting dependency is a protocol with a small,
hand-rolled test double - no mocking framework. `BLECardioMonitorMock` substitutes for
`CardioMonitorServing` (with `emit(_:)` to push readings and call counters to assert on),
`CardioRiskPredictorMock` substitutes for `CardioRiskPredicting` (stubbed prediction or
error). All four test files (`CardioGuardTests`, `DashboardViewModelTests`,
`CardioAIPredictionTests`, plus the parser tests) use Swift Testing (`@Suite`/`@Test`,
`#expect`, tagged `.success`/`.failure` via `Tag+Extension.swift`) rather than XCTest,
and consistently pair a success-path test with a boundary-value test for every threshold
(e.g. "BPM exactly 50 does NOT trigger bradycardia").

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

**iOS side:**
* `AppContainer.makeCardioMonitorService()` decides mock-vs-real with
  `#if targetEnvironment(simulator)` - a compile-time flag baked into the composition root
  rather than an injectable configuration. It means the real `BLECardioMonitorRepository`
  can never be exercised in Simulator, and the mock can't be forced on a device build
  without recompiling. A `RunEnvironment` value picked once at launch (or per scheme) would
  make that choice explicit and overridable instead of implicit.
* `BLECardioMonitorMock` does double duty as the Simulator's demo data generator (shipped
  in the app target, used by `AppContainer`) *and* as the test suite's mock (it carries
  `startMonitoringCallCount`/`stopMonitoringCallCount` purely for assertions). Convenient
  short-term, but a change made to satisfy one caller can quietly break the other, and test
  instrumentation ships inside the app bundle. Splitting it into a shipped
  `SimulatedCardioMonitorService` and a test-only spy would be cleaner.
* The Scanner feature isn't actually wired into the DI graph: `AppContainer.makeScannerViewModel()`
  is dead code (`ScannerUIView` constructs `ScannerViewModel()` directly), and the
  `AppRouter`/`AppScreen` navigation stack injected into the environment by
  `CardioGuardApp` is unused too - Dashboard→Scanner navigation is a local
  `@State private var showScanner: Bool` + `.sheet`. Either finish wiring Scanner through
  `AppContainer`/`AppRouter`, or delete the unused router and factory - as it stands there's
  more navigation architecture present than the app actually exercises.
* Scanner itself is fully simulated (`Task.sleep` + two hardcoded `DiscoveredDevice` values)
  and never touches `BLECentralManaging` - "scan for a device" and "monitor an already-known
  device" are two separate code paths that have never been connected. Handing a discovered
  peripheral from the scanner into `BLECentralManager` would close that gap.
* `BLEDataParser`'s `corruptedData` guard (`bpm/slic/dlic >= 0`) can never actually fire -
  the values are decoded via `Int(payload[n])` from `UInt8`, which is never negative. Worth
  either deleting the dead branch or, better, replacing it with a real
  physiological-plausibility check (e.g. reject BPM > 250) so malformed sensor data is
  caught at the parsing boundary instead of only at the clinical-threshold layer.
* `BLECentralManager` scans for the real Bluetooth Heart Rate Service (`0x180D`) /
  Measurement characteristic (`0x2A37`) UUIDs but decodes payloads with the same custom
  3-byte `[BPM, Systolic, Diastolic]` schema as the mock. The standard GATT Heart Rate
  Measurement characteristic doesn't carry blood pressure at all (that lives in an entirely
  separate GATT Blood Pressure Service with its own wire format), so this implementation
  would not interoperate with a real off-the-shelf heart rate strap - fine for an exercise
  built around a simulated payload, but worth being explicit that it isn't GATT-compliant.
* `AppTheme` (`Core/Theme/AppTheme.swift`) defines colors, radii, spacing, and animation
  curves as design tokens, but neither `DashBoardUIView` nor `ScannerUIView` references them
  - both hardcode the equivalent literals inline. Adopting the tokens would turn a future
  theming/dark-mode pass into a one-place change.
* `DashboardViewModel` has accumulated three responsibilities - relaying live metrics,
  running the instant rule engine, and running the rolling AI-window prediction - behind one
  private mutable buffer (`recentReadings`). Still small and well-tested today, but the
  natural next refactor is extracting the window bookkeeping into its own type (a small
  `ReadingWindow` buffer, or a second use case paralleling `EvaluateCardioRiskUseCase`) so
  the ViewModel goes back to pure orchestration.
* A handful of naming/formatting rough edges, harmless but worth a cleanup pass: the parser
  file is literally named `" BLEDataParser.swift"` with a leading space; the DI folder is
  `Core/DependecyInjection` (missing an "n"); `CardioVascularMetrics` mixes casing
  conventions (`SystoliC`, `Timestamp` vs. a computed `TimeStamp`); and
  `EvaluateCardioRiskUseSG` reads as a truncated/typo'd sibling of
  `EvaluateCardioRiskUseCase`. None of these affect behavior, but they're the kind of thing
  that costs a new contributor a double-take.
* `DashboardViewModelTests` and `EvaluateCardioRiskUseCaseTests` both exercise the exact same
  clinical-threshold matrix (every alert × every boundary value) - one at the Domain/use-case
  level, one end-to-end through the ViewModel. That's a reasonable belt-and-suspenders split
  (unit-level correctness vs. wiring correctness), but it does mean any future threshold
  change has to be updated in two places at once.

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
