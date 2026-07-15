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
