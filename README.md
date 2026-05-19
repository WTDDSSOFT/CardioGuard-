# 📋 Technical Challenge: CardioGuard IoT Monitor

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
