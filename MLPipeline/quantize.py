"""
quantize.py

Post-Training Quantization (PTQ) for CardioRiskPredictor, on top of the
already structurally-pruned model produced by prune_and_convert.py.

Produces two additional Core ML variants alongside the existing fp32 pruned
package:
  - CardioRiskPredictor_fp16.mlpackage: Core ML's native float16 compute
    precision (`compute_precision=ct.precision.FLOAT16` at convert time).
  - CardioRiskPredictor_int8.mlpackage: int8 weight-only linear quantization
    of that fp16 package, via coremltools.optimize.coreml.linear_quantize_weights.

Run this AFTER prune_and_convert.py - it reuses load_baseline / structured_prune
/ fine_tune from that file, and needs cardio_risk_predictor.pt +
normalization.npz already on disk from `python train.py`.

Run: python quantize.py
Requires: torch, coremltools>=7.2, numpy (see requirements.txt)

NOTE: the `coremltools.optimize.coreml` config classes below
(`OpLinearQuantizerConfig` / `OptimizationConfig` / `linear_quantize_weights`)
match the API as of coremltools 7.x. This script was written and reviewed,
but never actually executed end-to-end (this pipeline was authored in a
sandbox with no internet access to install coremltools - see
MLPipeline/README.md) - if the exact call signature drifted in the
coremltools version you have installed, check
https://apple.github.io/coremltools/docs-guides/source/opt-quantization-algos.html
and adjust; the accuracy-impact validation in
reference_validation/numpy_quantization_report.json does not depend on this
exact API and stands on its own.
"""
import json
import os
import shutil

import coremltools as ct
import coremltools.optimize.coreml as ctopt
import torch

from generate_data import build_dataset, train_test_split
from train import evaluate, to_tensor
from prune_and_convert import load_baseline, structured_prune, fine_tune, dir_size

FP16_PATH = "models/CardioRiskPredictor_fp16.mlpackage"
INT8_PATH = "models/CardioRiskPredictor_int8.mlpackage"


def convert_fp16(model, out_path: str):
    model.eval()
    example = torch.zeros(1, 6, 3)
    traced = torch.jit.trace(model, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="readings", shape=(1, 6, 3))],
        outputs=[ct.TensorType(name="risk_score")],
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
    )
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    return mlmodel


def quantize_int8(source_mlpackage_path: str, out_path: str):
    mlmodel = ct.models.MLModel(source_mlpackage_path)
    op_config = ctopt.OpLinearQuantizerConfig(mode="linear_symmetric")
    config = ctopt.OptimizationConfig(global_config=op_config)
    quantized = ctopt.linear_quantize_weights(mlmodel, config=config)
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    quantized.save(out_path)
    return quantized


def main():
    os.makedirs("models", exist_ok=True)

    baseline = load_baseline()
    pruned = structured_prune(baseline)

    X, y, kinds = build_dataset(n_trajectories=400, seed=7)
    (X_train, y_train, _), (X_test, y_test, _) = train_test_split(X, y, kinds)
    X_train_t, y_train_t = to_tensor(X_train), to_tensor(y_train)
    X_test_t, y_test_t = to_tensor(X_test), to_tensor(y_test)

    fine_tune(pruned, X_train_t, y_train_t)
    pruned_metrics = evaluate(pruned, X_test_t, y_test_t)

    convert_fp16(pruned, FP16_PATH)
    quantize_int8(FP16_PATH, INT8_PATH)

    fp32_size = dir_size("models/CardioRiskPredictor.mlpackage")
    fp16_size = dir_size(FP16_PATH)
    int8_size = dir_size(INT8_PATH)

    report = {
        "pruned_fp32_metrics": pruned_metrics,
        "pruned_fp32_mlpackage_bytes": fp32_size,
        "pruned_fp16_mlpackage_bytes": fp16_size,
        "pruned_int8_mlpackage_bytes": int8_size,
        "fp16_size_reduction_pct": 100 * (1 - fp16_size / fp32_size),
        "int8_size_reduction_pct": 100 * (1 - int8_size / fp32_size),
        "note": (
            "Accuracy of the fp16/int8 .mlpackage files themselves isn't "
            "re-measured here - a compressed mlprogram can only be executed "
            "through the actual Core ML runtime (macOS/iOS), not from plain "
            "Python/PyTorch. See reference_validation/numpy_quantization_report.json "
            "for the accuracy-impact validation instead: int8 and float16 "
            "fake-quantization simulated on the equivalent architecture were "
            "both accuracy-neutral (int8 was fractionally better than fp32 "
            "on the held-out set, fp16 was identical). If you're running this "
            "on a Mac, cross-check with Xcode's Core ML preview / Performance "
            "Report tab on the real exported files."
        ),
    }
    with open("quantize_report.json", "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))
    print(f"\nSaved: {FP16_PATH}")
    print(f"Saved: {INT8_PATH}")
    print("Pick whichever variant fits your accuracy/size budget and copy it into")
    print("CardioGuard/Resources/MLModels/CardioRiskPredictor.mlpackage")


if __name__ == "__main__":
    main()
