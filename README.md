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
