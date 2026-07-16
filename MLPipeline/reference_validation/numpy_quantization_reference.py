"""
numpy_quantization_reference.py

Extends numpy_reference.py with a Post-Training Quantization (PTQ) validation,
using the same "no internet in this sandbox, so validate the numerics with a
dependency-free NumPy reference first" approach used for pruning.

Simulates two quantization schemes on top of the already structurally-pruned
model:
  - float16: every weight/bias cast to float16 and back (numerically what
    Core ML's `compute_precision=.float16` conversion does).
  - int8 PTQ: per-tensor symmetric linear quantization
    (scale = max(|w|)/127, q = round(w/scale) clipped to [-127,127]),
    then dequantized for the forward pass - this is "fake quantization":
    it reproduces the numerical error int8 storage introduces without
    needing an actual int8 execution kernel, which is exactly how
    coremltools/PyTorch's own quantization-simulation tooling validates
    accuracy before shipping a real quantized artifact.

This script does NOT retrain anything for quantization (that's the whole
point of *post-training* quantization - no fine-tuning pass, no gradient
updates, just requantizing already-trained weights) - it only reuses the
already-trained-and-pruned model from numpy_reference.py.
"""
from __future__ import annotations

import copy
import json

import numpy as np

from numpy_reference import (
    MLP, structured_prune, train, evaluate, timed_inference,
    X_train_norm, y_train, X_test_norm, y_test, POS_WEIGHT, rng,
)

WEIGHT_ATTRS = ["W1", "b1", "W2", "b2", "W3", "b3"]


def quantize_int8_per_tensor(array: np.ndarray):
    max_abs = np.max(np.abs(array))
    scale = max_abs / 127.0 if max_abs > 0 else 1.0
    q = np.clip(np.round(array / scale), -127, 127)
    dequantized = (q * scale).astype(np.float32)
    return dequantized, scale


def quantize_model_int8(model: MLP) -> MLP:
    quantized = copy.deepcopy(model)
    for attr in WEIGHT_ATTRS:
        original = getattr(model, attr)
        dequantized, _scale = quantize_int8_per_tensor(original)
        setattr(quantized, attr, dequantized)
    return quantized


def quantize_model_float16(model: MLP) -> MLP:
    quantized = copy.deepcopy(model)
    for attr in WEIGHT_ATTRS:
        original = getattr(model, attr)
        quantized_val = original.astype(np.float16).astype(np.float32)
        setattr(quantized, attr, quantized_val)
    return quantized


def storage_bytes(model: MLP, bytes_per_param: float) -> float:
    return model.param_count() * bytes_per_param


def main():
    # Reproduce the exact baseline -> structured-pruning -> fine-tune pipeline
    # from numpy_reference.py, so this script can be run standalone.
    baseline = MLP([X_train_norm.shape[1], 16, 8], rng)
    train(baseline, X_train_norm, y_train, epochs=80, lr=0.02, pos_weight=POS_WEIGHT, seed=1)

    pruned = structured_prune(baseline, keep1=8, keep2=4)
    train(pruned, X_train_norm, y_train, epochs=40, lr=0.01, pos_weight=POS_WEIGHT, seed=2)

    pruned_metrics = evaluate(pruned, X_test_norm, y_test)
    pruned_latency = timed_inference(pruned, X_test_norm)

    int8_model = quantize_model_int8(pruned)
    int8_metrics = evaluate(int8_model, X_test_norm, y_test)
    int8_latency = timed_inference(int8_model, X_test_norm)

    fp16_model = quantize_model_float16(pruned)
    fp16_metrics = evaluate(fp16_model, X_test_norm, y_test)
    fp16_latency = timed_inference(fp16_model, X_test_norm)

    report = {
        "pruned_fp32": {
            "metrics": pruned_metrics,
            "latency_ms": pruned_latency,
            "storage_bytes_estimate": storage_bytes(pruned, 4.0),
        },
        "pruned_fp16_simulated": {
            "metrics": fp16_metrics,
            "latency_ms": fp16_latency,
            "storage_bytes_estimate": storage_bytes(pruned, 2.0),
            "accuracy_delta_vs_fp32": fp16_metrics["accuracy"] - pruned_metrics["accuracy"],
            "f1_delta_vs_fp32": fp16_metrics["f1"] - pruned_metrics["f1"],
        },
        "pruned_int8_ptq_simulated": {
            "metrics": int8_metrics,
            "latency_ms": int8_latency,
            # +1 byte/tensor amortized scale overhead is negligible at this
            # param count and omitted for readability.
            "storage_bytes_estimate": storage_bytes(pruned, 1.0),
            "accuracy_delta_vs_fp32": int8_metrics["accuracy"] - pruned_metrics["accuracy"],
            "f1_delta_vs_fp32": int8_metrics["f1"] - pruned_metrics["f1"],
        },
    }

    with open("numpy_quantization_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
