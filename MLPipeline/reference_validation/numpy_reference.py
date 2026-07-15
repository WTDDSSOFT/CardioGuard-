"""
numpy_reference.py

Self-contained reference implementation used to validate the CardioGuard
early-warning model *before* running the real PyTorch + coremltools pipeline
(this sandbox has no internet access to install torch/coremltools, so this
script proves the dataset + architecture + structured-pruning approach with
only numpy, which is what the shipped MLPipeline/train.py mirrors).

Architecture: 18 (6 readings x 3 vitals) -> Dense(16, ReLU) -> Dense(8, ReLU)
-> Dense(1, Sigmoid). Trained with Adam + weighted binary cross-entropy.

Structured pruning: whole neurons in the two hidden layers are removed
(ranked by L2 norm of their outgoing weights), not just individual weights
zeroed out. This is deliberate: unstructured (weight-level) pruning does not
shrink a dense matrix or reduce a Core ML package's size/latency unless the
runtime has sparse-kernel support. Structured pruning physically shrinks the
weight matrices, so the size/latency win is real on every backend, including
Core ML on iPhone.
"""
from __future__ import annotations

import json
import os
import sys
import time

import numpy as np

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from generate_data import build_dataset, train_test_split, WINDOW_SIZE

rng = np.random.default_rng(42)

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------
X, y, kinds = build_dataset(n_trajectories=400, seed=7)
(X_train, y_train, _), (X_test, y_test, kinds_test) = train_test_split(X, y, kinds)

X_train_flat = X_train.reshape(len(X_train), -1)
X_test_flat = X_test.reshape(len(X_test), -1)

mean = X_train_flat.mean(axis=0)
std = X_train_flat.std(axis=0) + 1e-6

X_train_norm = (X_train_flat - mean) / std
X_test_norm = (X_test_flat - mean) / std

POS_WEIGHT = (y_train == 0).sum() / max((y_train == 1).sum(), 1)


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
def init_layer(fan_in, fan_out, seed_rng):
    limit = np.sqrt(6.0 / (fan_in + fan_out))
    W = seed_rng.uniform(-limit, limit, size=(fan_in, fan_out))
    b = np.zeros(fan_out)
    return W, b


class MLP:
    def __init__(self, sizes, seed_rng):
        self.sizes = sizes
        self.W1, self.b1 = init_layer(sizes[0], sizes[1], seed_rng)
        self.W2, self.b2 = init_layer(sizes[1], sizes[2], seed_rng)
        self.W3, self.b3 = init_layer(sizes[2], 1, seed_rng)
        self._adam_state = {}

    def param_count(self):
        return (self.W1.size + self.b1.size + self.W2.size + self.b2.size
                + self.W3.size + self.b3.size)

    def forward(self, X, cache=False):
        z1 = X @ self.W1 + self.b1
        a1 = np.maximum(0, z1)
        z2 = a1 @ self.W2 + self.b2
        a2 = np.maximum(0, z2)
        z3 = a2 @ self.W3 + self.b3
        out = 1 / (1 + np.exp(-z3))
        if cache:
            return out, (X, z1, a1, z2, a2, z3)
        return out

    def backward(self, cache, y_true, pos_weight):
        X, z1, a1, z2, a2, z3 = cache
        n = X.shape[0]
        p = 1 / (1 + np.exp(-z3)).reshape(-1)
        y_true = y_true.reshape(-1)

        weight = np.where(y_true == 1, pos_weight, 1.0)
        dz3 = ((p - y_true) * weight).reshape(-1, 1) / n

        dW3 = a2.T @ dz3
        db3 = dz3.sum(axis=0)

        da2 = dz3 @ self.W3.T
        dz2 = da2 * (z2 > 0)
        dW2 = a1.T @ dz2
        db2 = dz2.sum(axis=0)

        da1 = dz2 @ self.W2.T
        dz1 = da1 * (z1 > 0)
        dW1 = X.T @ dz1
        db1 = dz1.sum(axis=0)

        return dict(W1=dW1, b1=db1, W2=dW2, b2=db2, W3=dW3, b3=db3)

    def adam_step(self, grads, lr=0.01, betas=(0.9, 0.999), eps=1e-8):
        if not self._adam_state:
            self._adam_state = {k: dict(m=np.zeros_like(getattr(self, k)),
                                         v=np.zeros_like(getattr(self, k)), t=0)
                                 for k in grads}
        for k, g in grads.items():
            state = self._adam_state[k]
            state["t"] += 1
            state["m"] = betas[0] * state["m"] + (1 - betas[0]) * g
            state["v"] = betas[1] * state["v"] + (1 - betas[1]) * (g ** 2)
            m_hat = state["m"] / (1 - betas[0] ** state["t"])
            v_hat = state["v"] / (1 - betas[1] ** state["t"])
            update = lr * m_hat / (np.sqrt(v_hat) + eps)
            setattr(self, k, getattr(self, k) - update)


def train(model, X, y, epochs=80, batch_size=64, lr=0.01, pos_weight=1.0, seed=0):
    n = len(y)
    local_rng = np.random.default_rng(seed)
    for epoch in range(epochs):
        order = local_rng.permutation(n)
        for start in range(0, n, batch_size):
            idx = order[start:start + batch_size]
            _, cache = model.forward(X[idx], cache=True)
            grads = model.backward(cache, y[idx], pos_weight)
            model.adam_step(grads, lr=lr)
    return model


def evaluate(model, X, y, threshold=0.5):
    p = model.forward(X).reshape(-1)
    pred = (p >= threshold).astype(int)
    tp = int(((pred == 1) & (y == 1)).sum())
    fp = int(((pred == 1) & (y == 0)).sum())
    fn = int(((pred == 0) & (y == 1)).sum())
    tn = int(((pred == 0) & (y == 0)).sum())
    accuracy = (tp + tn) / len(y)
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    return dict(accuracy=accuracy, precision=precision, recall=recall, f1=f1,
                tp=tp, fp=fp, fn=fn, tn=tn)


def timed_inference(model, X, n_repeats=20):
    # single-sample latency, averaged
    sample = X[:1]
    start = time.perf_counter()
    for _ in range(n_repeats):
        model.forward(sample)
    elapsed = (time.perf_counter() - start) / n_repeats
    return elapsed * 1000  # ms


# ---------------------------------------------------------------------------
# Structured pruning: drop whole neurons ranked by L2 norm of outgoing weights
# ---------------------------------------------------------------------------
def structured_prune(model, keep1, keep2):
    importance1 = np.linalg.norm(model.W2, axis=1)  # how much each L1 neuron feeds forward
    keep_idx1 = np.argsort(-importance1)[:keep1]
    keep_idx1.sort()

    importance2 = np.linalg.norm(model.W3, axis=1)
    keep_idx2 = np.argsort(-importance2)[:keep2]
    keep_idx2.sort()

    pruned = MLP([model.sizes[0], keep1, keep2], rng)
    pruned.W1 = model.W1[:, keep_idx1].copy()
    pruned.b1 = model.b1[keep_idx1].copy()
    pruned.W2 = model.W2[np.ix_(keep_idx1, keep_idx2)].copy()
    pruned.b2 = model.b2[keep_idx2].copy()
    pruned.W3 = model.W3[keep_idx2, :].copy()
    pruned.b3 = model.b3.copy()
    return pruned


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
def main():
    report = {}

    baseline = MLP([X_train_norm.shape[1], 16, 8], rng)
    report["baseline_params"] = baseline.param_count()

    train(baseline, X_train_norm, y_train, epochs=80, lr=0.02, pos_weight=POS_WEIGHT, seed=1)
    baseline_metrics = evaluate(baseline, X_test_norm, y_test)
    baseline_latency = timed_inference(baseline, X_test_norm)

    report["baseline_metrics"] = baseline_metrics
    report["baseline_latency_ms"] = baseline_latency

    pruned = structured_prune(baseline, keep1=8, keep2=4)
    report["pruned_params"] = pruned.param_count()
    pre_finetune_metrics = evaluate(pruned, X_test_norm, y_test)

    train(pruned, X_train_norm, y_train, epochs=40, lr=0.01, pos_weight=POS_WEIGHT, seed=2)
    pruned_metrics = evaluate(pruned, X_test_norm, y_test)
    pruned_latency = timed_inference(pruned, X_test_norm)

    report["pruned_pre_finetune_metrics"] = pre_finetune_metrics
    report["pruned_metrics"] = pruned_metrics
    report["pruned_latency_ms"] = pruned_latency

    report["param_reduction_pct"] = 100 * (1 - report["pruned_params"] / report["baseline_params"])
    report["latency_change_pct"] = 100 * (pruned_latency / baseline_latency - 1)

    # Per-trajectory-kind breakdown on the (harder, non-normal) cases
    p_test = baseline.forward(X_test_norm).reshape(-1)
    pred_test = (p_test >= 0.5).astype(int)
    breakdown = {}
    for k in sorted(set(kinds_test)):
        mask = kinds_test == k
        if mask.sum() == 0:
            continue
        breakdown[k] = dict(
            n=int(mask.sum()),
            positive_rate=float(y_test[mask].mean()),
            recall=float((pred_test[mask][y_test[mask] == 1] == 1).mean()) if (y_test[mask] == 1).any() else None,
        )
    report["baseline_breakdown_by_kind"] = breakdown

    with open("numpy_reference_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
