# CardioGuard — On-Device Early-Warning Model

This folder is a self-contained training + optimization + Core ML conversion
pipeline for **CardioRiskPredictor**, an on-device model that complements the
app's deterministic clinical-threshold engine (`EvaluateCardioRiskUseCase`)
with a *predictive* signal: the probability that a cardiovascular crisis is
about to happen in the next few BLE readings, learned from the trend across
the last 6 readings.

## Why this exists

`EvaluateCardioRiskUseCase` is a rule engine: it flags a crisis the instant a
single reading crosses a hard threshold (Systolic > 140, BPM < 50, ...). That
is correct and necessary, but it is reactive by definition — it cannot warn
the user *before* the threshold is crossed. `CardioRiskPredictor` looks at the
shape of the last 6 readings (a mini time series) and predicts whether a
threshold will be crossed within the next 3 readings, catching gradual
deterioration trends the rule engine structurally cannot see.

The two are meant to run side by side, not to replace one another: the rule
engine gives instant, explainable, zero-latency ground truth; the model gives
earlier, probabilistic warning.

## Pipeline

```
generate_data.py        synthetic patient trajectories + sliding-window dataset
model.py                CardioRiskNet (PyTorch): 18 -> 16 -> 8 -> 1, normalization baked in
train.py                trains the baseline model, evaluates, saves cardio_risk_predictor.pt
prune_and_convert.py    structured neuron pruning + fine-tune + Core ML export (.mlpackage)
reference_validation/   numpy-only reimplementation, used to validate the approach (see below)
```

### Run it (needs internet access + a machine that can install torch/coremltools)

```bash
pip install -r requirements.txt
python train.py               # -> cardio_risk_predictor.pt, train_report.json
python prune_and_convert.py   # -> models/CardioRiskPredictor.mlpackage, prune_convert_report.json
```

Then drag `models/CardioRiskPredictor.mlpackage` into
`CardioGuard/Resources/MLModels/` in Xcode (the project uses Xcode 16
synchronized groups, so it's picked up automatically — no `.pbxproj` editing
needed). `CoreMLCardioRiskPredictor.swift` loads it by name at runtime and
fails soft (predictions simply become unavailable) if the file is missing, so
the app still builds and runs without it.

> **Note on how this was built:** this pipeline was originally authored in a
> sandbox with no internet access, so `torch` and `coremltools` could not be
> installed to run `train.py` / `prune_and_convert.py` there. The exact same
> dataset generator, architecture, and structured-pruning strategy were
> instead validated end-to-end with a dependency-free NumPy reimplementation
> (`reference_validation/`), which *was* run at the time, producing the
> numbers that used to live in this section. The pipeline has since been run
> for real (see below) — those NumPy numbers are kept in
> `reference_validation/` as a sanity-check artifact, but the table below is
> now the authoritative one.
>
> **Environment note:** on a plain `pip install -r requirements.txt`, pick a
> Python version that has a *prebuilt* `coremltools` wheel (3.9–3.13 as of
> coremltools 9.0 — check `pypi.org/pypi/coremltools/<version>/json`).
> Python 3.14 has no prebuilt wheel yet, so pip silently builds coremltools
> from sdist, which is missing the compiled `libcoremlpython` /
> `libmilstoragepython` extensions — conversion runs but `mlmodel.save(...)`
> fails with `RuntimeError: BlobWriter not loaded`. Re-running the venv under
> Python 3.12 fixed it. Separately, `torch.jit.trace` on very recent torch
> (2.13.0, newer than the 2.7.0 coremltools has been tested against) combined
> with NumPy 2.x triggered a `TypeError: only 0-dimensional arrays can be
> converted to Python scalars` inside coremltools' `int()`-cast op, coming
> from `model.py`'s `readings.reshape(readings.shape[0], -1)` (tracing a
> dynamic `.shape[0]` lookup). Switching to `readings.flatten(start_dim=1)`
> (identical result, no dynamic shape read) avoided the op entirely.

## Validated results (`train_report.json` / `prune_convert_report.json`, real PyTorch + Core ML run)

Dataset: 400 synthetic patient trajectories (40 timesteps each) — a mix of
stable-normal, gradually-drifting-into-crisis (hypertensive, hypotensive,
tachycardic, bradycardic), and normal-with-a-one-off-sensor-artifact
trajectories — sliced into 12,800 six-reading windows, 20% held out for
testing (2,560 windows). Run with Python 3.12, torch 2.13.0, coremltools 9.0.

| | Baseline (449 params) | Structured-pruned (193 params) |
|---|---|---|
| Accuracy | 94.41% | 95.51% |
| Precision | 69.54% | 75.14% |
| Recall | 92.26% | 91.58% |
| F1 | 0.793 | 0.825 |

**57.0% of parameters removed (449 → 193) with no accuracy or F1
regression** (16→8 neurons in the first hidden layer, 8→4 in the second,
pruned by L2 norm of outgoing weights, then fine-tuned for 40 epochs).
Pre-fine-tune, the pruned model dips sharply (accuracy 86.0%, F1 0.574) as
expected — fine-tuning fully recovers it.

`.mlpackage` on-disk size: baseline 5,581 bytes → pruned 4,975 bytes
(**10.9% smaller**). At this parameter count the model is dominated by
Core ML's fixed `mlprogram` container overhead, not tensor payload, so the
size win is much smaller in percentage terms than the 57% parameter
reduction — don't expect the two percentages to track each other at this
scale. The latency/footprint win from the *shape* reduction (16→8, 8→4) is
still real; see the note on latency below.

Recall broken down by scenario (baseline model):

| Scenario | Recall |
|---|---|
| Hypertensive drift | 99.1% |
| Hypotensive drift | 98.5% |
| Bradycardic drift | 94.4% |
| Tachycardic drift | 88.9% |
| One-off sensor artifact (spike then revert) | 0% |

The last row is deliberate, not a bug: the model was trained on gradual
multi-step trends, so it does not fire on a single-sample artifact that
reverts immediately — that case is already instantly and correctly caught by
the deterministic `EvaluateCardioRiskUseCase` the moment the spike happens.
The predictive model and the rule engine cover different failure modes.

**How this compares to the earlier NumPy validation:** the headline
conclusion holds — same architecture, same 449→193 (57.0%) parameter
reduction (identical, since that's an architectural choice independent of
the training framework), accuracy in the 94–96% range and recall consistently
above ~90% in both. Absolute metrics differ by a few points (e.g. baseline
accuracy 94.4% here vs. 95.98% in the NumPy run; baseline precision 69.5% vs.
76.8%) because the NumPy reference is an independent from-scratch
implementation of the training loop — different weight initialization,
Adam implementation details, and floating-point paths than PyTorch's — not
a discrepancy in the approach itself. The one divergence worth flagging: the
pre-fine-tune pruned model collapsed to 0% precision/recall in the NumPy run
but only dipped to 81.5% recall here; both fully recover after fine-tuning
to an equivalent result, so it doesn't change the conclusion, but it shows
the NumPy reference is a *more pessimistic* stand-in for the pre-fine-tune
dip than real PyTorch training, not an exact numerical proxy.

**On pruning technique:** neurons are removed *structurally* (whole rows/
columns of the weight matrices), not zeroed out in place. Unstructured
(weight-level) pruning doesn't shrink a dense matrix or reduce inference
latency unless the runtime has sparse-kernel support — Core ML's default
compute path does not exploit unstructured sparsity, so it wouldn't produce a
real win on-device. Structured pruning shrinks the actual tensor dimensions,
so the size/latency benefit is real on any backend, Core ML included.

**On latency:** the NumPy reference model runs in ~0.004ms per sample either
way — at this parameter count (hundreds, not millions), latency in a
Python/NumPy microbenchmark is dominated by fixed interpreter overhead, not
by FLOPs, so it isn't representative of on-device timing. The actual Core ML
latency and memory footprint should be measured with Xcode's Core ML
Performance Report (Product > Profile > Core ML template) once
`CardioRiskPredictor.mlpackage` is built into the app on a real device.

## Reproducing the reference validation

```bash
cd reference_validation
python3 numpy_reference.py
```

No dependencies beyond NumPy. Prints and saves `numpy_reference_report.json`.

---

## 🏗️ Architecture Deep-Dive

### `generate_data.py`: synthetic trajectories with a *predictive* label

There's no real patient data here - every reading is synthesized. The interesting part
isn't the noise model, it's the **labeling scheme**, because it's what makes the model
predictive rather than just a second copy of the rule engine:

* `is_crisis(bpm, systolic, diastolic)` is a literal port of the same thresholds as
  `EvaluateCardioRiskUseCase.swift` (the doc comment says so explicitly) - tachycardia
  `> 120`, bradycardia `< 50`, hypertension `systolic > 140 OR diastolic > 90`,
  hypotension `systolic < 90`.
* Six trajectory kinds are generated by `make_trajectory()`, drawn per `TRAJECTORY_MIX`:
  `normal` (40%, flat Gaussian noise around a healthy baseline), four `_drifting_trajectory`
  kinds - `hypertensive`/`hypotensive`/`tachycardic`/`bradycardic` (12–14% each, a random
  onset between step 10–25, then a non-linear ramp, `ramp ** 1.3`, toward a hand-picked
  crisis "target" vitals dict), and `normal_with_artifact` (10%, a stable trajectory with a
  single 1–2-timestep spike on *one* feature, simulating a transient sensor glitch that
  reverts).
* `windows_from_trajectory()` slides a `WINDOW_SIZE`-reading (6) window across each
  40-step trajectory and labels it `1` if `is_crisis` fires on **any of the next `HORIZON`
  (3) readings** - not on the window itself. This is the whole point of the model: during
  the ramp, well before any individual reading actually crosses a threshold, the windows
  covering that ramp are already labeled positive, so the network is explicitly trained to
  recognize "heading toward crisis" rather than "currently in crisis" (which the rule
  engine already covers instantly, for free).
* `build_dataset()` runs this over 400 trajectories and concatenates every trajectory's
  windows into one flat `(X, y, kinds)` triple - `kinds` (the trajectory label, e.g.
  `"hypertensive"`) is threaded through purely so results can be broken down by scenario
  later (see the recall table above).

### `model.py` + `train.py`: a small MLP with normalization inside the model

`CardioRiskNet` is `18 → Dense(16, ReLU) → Dense(8, ReLU) → Dense(1, Sigmoid)`, 449
parameters. Two choices worth calling out:

* `mean`/`std` are registered as PyTorch buffers and applied inside `forward()`, computed
  from the **training split only** (`train.py` never touches `X_test` when computing
  normalization stats) - so there's no test-set leakage through the normalization step, and
  the exported Core ML model takes raw vitals directly, with no preprocessing to replicate
  in Swift.
* Class imbalance (crises are the minority class) is handled with a `pos_weight` applied
  inside `BCELoss` (`(y_train == 0).sum() / (y_train == 1).sum()`), not by
  oversampling/undersampling - a standard, cheap way to keep the loss from being dominated
  by the majority "normal" windows.

### `prune_and_convert.py`: why *this* pruning heuristic

Neuron importance is ranked by the **L2 norm of each neuron's outgoing weights** -
`model.fc2.weight.norm(dim=0)` for layer 1's neurons, i.e. "how much does the *next* layer
actually listen to this neuron", not how large the neuron's own incoming weights are. The
top-`K` neurons by that score are kept (16→8, 8→4), the rest of the weight matrix is
sliced out entirely (not zeroed - the tensors literally get smaller), and the smaller
network is fine-tuned for 40 epochs at a lower learning rate (0.005 vs. the initial 0.01,
since it's already close to converged). Conversion then traces the model with
`torch.jit.trace` on a fixed `(1, 6, 3)` example and calls `ct.convert(..., inputs=[TensorType(name="readings", shape=(1,6,3))], outputs=[TensorType(name="risk_score")], minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram")`
- both the baseline and pruned model are converted, so the size/accuracy comparison in
this README is apples-to-apples through the same conversion path.

### `reference_validation/numpy_reference.py`: hand-derived, not just hand-run

This isn't a toy stand-in - it's a full from-scratch MLP with **manually derived forward
and backward passes** (explicit `dW3 = a2.T @ dz3`-style gradient equations) and a
hand-rolled Adam optimizer (bias-corrected first/second moments computed by hand), because
no autograd framework was available. It imports `generate_data.py` directly (so the
dataset is identical to what `train.py` uses, not a re-implementation of that too) and
reimplements the same structured-pruning heuristic (`np.linalg.norm(model.W2, axis=1)`)
independently. Its value was proving the *approach* - architecture, labeling scheme,
pruning strategy - end-to-end before torch/coremltools could be installed; see "Validated
results" above for how its numbers compare to the real run.

### Trade-offs and honest limitations

* **The train/test split happens at the window level, not the trajectory level.**
  `train_test_split()` shuffles and splits all 12,800 windows from all 400 trajectories
  together, so two windows that overlap by 5 of their 6 readings (adjacent windows from the
  same simulated patient) can land on opposite sides of the split. That's a real form of
  leakage - the "held-out" test set isn't fully independent of training data - and it likely
  makes the reported accuracy/F1 somewhat optimistic versus a true unseen-patient
  evaluation. Splitting by trajectory (all windows from a given simulated patient entirely
  in train *or* test) would be a more honest generalization estimate.
* **Every number in this README describes synthetic data only.** The noise levels, ramp
  shape (`ramp ** 1.3`), crisis "target" vitals, and trajectory-kind mix are all
  hand-picked to look plausible, not derived from real patient data or a validated
  physiological model. Nothing here says anything about how this model would perform on a
  real BLE device stream - that would require real (or at least more rigorously simulated)
  data to even start evaluating.
* **The reported metrics use a 0.5 decision threshold; the app doesn't.**
  `train.py`/`prune_and_convert.py`'s `evaluate()` computes accuracy/precision/recall/F1 at
  `p >= 0.5`. `AIRiskPrediction.isElevated` on the Swift side uses `riskScore >= 0.6`
  ("favor recall over precision" per its doc comment) - a deliberate, different operating
  point. That's a reasonable choice, but it means the headline metrics in this README
  don't describe the exact threshold the dashboard actually acts on; a table at 0.6 would
  be the more honest number to show alongside the 0.5 one.
* **No validation split, no early stopping, no hyperparameter search.** Epoch counts (80 /
  40), learning rates (0.01 / 0.005), and the pruning keep-counts (8, 4) are all fixed
  constants chosen by hand, not tuned against a held-out validation set distinct from the
  test set used for the numbers in this README. In particular, the keep-counts weren't
  chosen via any accuracy-vs-size sweep (e.g. trying `keep1 ∈ {4,6,8,10,12}`) - "57%
  reduction, no regression" is true at this one point on the curve, not necessarily the
  best point on it.
* **Pruning importance is a simple, cheap heuristic** (outgoing-weight L2 norm per
  neuron), which doesn't detect redundant-but-individually-important neurons (two
  correlated neurons can each score well while being interchangeable together). More
  principled methods exist (greedy remove-and-re-evaluate, Taylor-expansion importance),
  but at 449 parameters the cost/benefit clearly favors the simple heuristic - just worth
  being explicit that "important" here means one specific, inexpensive definition of it.
* **The synthetic sensor-artifact scenario only ever corrupts one feature at a time.**
  `_normal_with_artifact` spikes a single vital (BPM *or* systolic *or* diastolic), so the
  dataset never exercises a simultaneous multi-channel glitch (e.g. a dropped BLE packet
  corrupting all three values at once) - the model's behavior on that kind of artifact is
  untested, not just "expected to be 0% recall by design" like the single-channel case
  documented above.
* **No automated tests for this pipeline's own logic.** The Swift side has thorough Swift
  Testing coverage of the equivalent business rule (`EvaluateCardioRiskUseCaseTests`); this
  pipeline has no analogous check on `windows_from_trajectory`'s slicing/label alignment or
  `structured_prune`'s index bookkeeping across `W1`/`W2`/`W3`. A handful of `pytest`
  assertions on window shapes, label offsets, and post-prune tensor shapes would be cheap
  insurance against a silent off-by-one quietly producing a worse model instead of a loud
  failure.
