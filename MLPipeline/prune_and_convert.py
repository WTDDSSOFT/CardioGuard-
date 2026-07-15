"""
prune_and_convert.py

1. Loads the baseline model trained by train.py.
2. Applies STRUCTURED pruning: whole neurons in the two hidden layers are
   removed (ranked by L2 norm of their outgoing weights), not just
   individual weights zeroed out. This physically shrinks the weight
   matrices, so the size/latency win is real on every backend - including
   Core ML on iPhone - unlike unstructured sparsity, which needs a sparse
   kernel to pay off.
3. Fine-tunes the smaller network for a few epochs to recover any accuracy
   lost by removing neurons.
4. Converts BOTH the baseline and the pruned model to Core ML (.mlpackage)
   via coremltools, and prints an on-disk size comparison.

Run: python prune_and_convert.py
Requires: torch, coremltools, numpy (see requirements.txt)

Output: models/CardioRiskPredictor.mlpackage (the pruned model - this is the
one that should be dragged into CardioGuard/Resources/MLModels/ in Xcode)
and models/CardioRiskPredictor_baseline.mlpackage (kept for comparison).
"""
import json
import os
import shutil

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn

from generate_data import build_dataset, train_test_split
from model import CardioRiskNet
from train import evaluate, to_tensor

KEEP_HIDDEN1 = 8   # pruned from 16
KEEP_HIDDEN2 = 4   # pruned from 8


def load_baseline() -> CardioRiskNet:
    checkpoint = torch.load("cardio_risk_predictor.pt", map_location="cpu")
    npz = np.load("normalization.npz")
    model = CardioRiskNet(hidden1=checkpoint["hidden1"], hidden2=checkpoint["hidden2"],
                           mean=npz["mean"], std=npz["std"])
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    return model


def structured_prune(model: CardioRiskNet) -> CardioRiskNet:
    importance1 = model.fc2.weight.detach().norm(dim=0)  # per-neuron L2 norm of outgoing weights
    keep_idx1 = importance1.argsort(descending=True)[:KEEP_HIDDEN1].sort().values

    importance2 = model.fc3.weight.detach().norm(dim=0)
    keep_idx2 = importance2.argsort(descending=True)[:KEEP_HIDDEN2].sort().values

    pruned = CardioRiskNet(hidden1=KEEP_HIDDEN1, hidden2=KEEP_HIDDEN2,
                            mean=model.mean.clone(), std=model.std.clone())

    with torch.no_grad():
        pruned.fc1.weight.copy_(model.fc1.weight[keep_idx1, :])
        pruned.fc1.bias.copy_(model.fc1.bias[keep_idx1])

        pruned.fc2.weight.copy_(model.fc2.weight[keep_idx2][:, keep_idx1])
        pruned.fc2.bias.copy_(model.fc2.bias[keep_idx2])

        pruned.fc3.weight.copy_(model.fc3.weight[:, keep_idx2])
        pruned.fc3.bias.copy_(model.fc3.bias)

    return pruned


def fine_tune(model, X, y, epochs=40, lr=0.005, batch_size=64):
    pos_weight = torch.tensor([(y.numpy() == 0).sum() / max((y.numpy() == 1).sum(), 1)])
    criterion = nn.BCELoss(reduction="none")
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    n = len(y)
    model.train()
    for _ in range(epochs):
        perm = torch.randperm(n)
        for start in range(0, n, batch_size):
            idx = perm[start:start + batch_size]
            optimizer.zero_grad()
            out = model(X[idx]).reshape(-1)
            weights = torch.where(y[idx] == 1, pos_weight, torch.tensor(1.0))
            loss = (criterion(out, y[idx]) * weights).mean()
            loss.backward()
            optimizer.step()
    model.eval()
    return model


def convert_to_coreml(model: CardioRiskNet, out_path: str):
    model.eval()
    example = torch.zeros(1, 6, 3)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="readings", shape=(1, 6, 3))],
        outputs=[ct.TensorType(name="risk_score")],
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )
    mlmodel.author = "William Dias Dos Santos"
    mlmodel.short_description = (
        "CardioGuard on-device early-warning model. Predicts the probability "
        "that a cardiovascular crisis (per EvaluateCardioRiskUseCase thresholds) "
        "occurs within the next 3 BLE readings, given the last 6 readings."
    )
    mlmodel.input_description["readings"] = "Last 6 readings, each [bpm, systolic, diastolic], raw units."
    mlmodel.output_description["risk_score"] = "Probability (0-1) of an imminent crisis."

    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)


def dir_size(path: str) -> int:
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            total += os.path.getsize(os.path.join(root, f))
    return total


def main():
    os.makedirs("models", exist_ok=True)

    baseline = load_baseline()

    X, y, kinds = build_dataset(n_trajectories=400, seed=7)
    (X_train, y_train, _), (X_test, y_test, _) = train_test_split(X, y, kinds)
    X_train_t, y_train_t = to_tensor(X_train), to_tensor(y_train)
    X_test_t, y_test_t = to_tensor(X_test), to_tensor(y_test)

    pre_prune_metrics = evaluate(baseline, X_test_t, y_test_t)

    pruned = structured_prune(baseline)
    pre_finetune_metrics = evaluate(pruned, X_test_t, y_test_t)

    fine_tune(pruned, X_train_t, y_train_t)
    post_finetune_metrics = evaluate(pruned, X_test_t, y_test_t)

    convert_to_coreml(baseline, "models/CardioRiskPredictor_baseline.mlpackage")
    convert_to_coreml(pruned, "models/CardioRiskPredictor.mlpackage")

    baseline_size = dir_size("models/CardioRiskPredictor_baseline.mlpackage")
    pruned_size = dir_size("models/CardioRiskPredictor.mlpackage")

    report = {
        "baseline_params": baseline.param_count(),
        "pruned_params": pruned.param_count(),
        "param_reduction_pct": 100 * (1 - pruned.param_count() / baseline.param_count()),
        "baseline_metrics": pre_prune_metrics,
        "pruned_pre_finetune_metrics": pre_finetune_metrics,
        "pruned_metrics": post_finetune_metrics,
        "baseline_mlpackage_bytes": baseline_size,
        "pruned_mlpackage_bytes": pruned_size,
        "mlpackage_size_reduction_pct": 100 * (1 - pruned_size / baseline_size),
    }
    with open("prune_convert_report.json", "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))
    print("\nSaved: models/CardioRiskPredictor.mlpackage  <- copy this into")
    print("CardioGuard/Resources/MLModels/ in the Xcode project.")


if __name__ == "__main__":
    main()
