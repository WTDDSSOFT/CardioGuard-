"""
generate_data.py

Synthetic dataset generator for the CardioGuard on-device early-warning model.

Design goal: the existing rule engine (EvaluateCardioRiskUseCase) only reacts
AFTER a threshold is crossed on a single reading. This generator produces
patient trajectories that gradually drift towards a cardiovascular crisis, so
a model trained on sliding windows of readings can learn to recognize the
*trend* a few samples before the hard threshold is actually breached.

Clinical thresholds (must match CardioGuard/Domain/UseCases/EvaluateCardioRiskUseCase.swift):
    Tachycardia:   BPM > 120
    Bradycardia:   BPM < 50
    Hypertension:  Systolic > 140 OR Diastolic > 90
    Hypotension:   Systolic < 90

No third-party dependencies: only numpy. Shared by both the numpy reference
validation (run inside this sandbox) and the PyTorch training script (meant
to run on a machine with internet access / Xcode).
"""
from __future__ import annotations

import numpy as np

WINDOW_SIZE = 6       # number of past readings the model looks at
HORIZON = 3            # how many readings ahead we're predicting a crisis for
T = 40                  # length of a simulated patient trajectory
FEATURE_NAMES = ("bpm", "systolic", "diastolic")

BASELINE = dict(bpm=72.0, systolic=115.0, diastolic=75.0)
NOISE_STD = dict(bpm=2.5, systolic=4.0, diastolic=3.0)

TARGETS = {
    "hypertensive": dict(bpm=88.0, systolic=158.0, diastolic=102.0),
    "hypotensive": dict(bpm=80.0, systolic=74.0, diastolic=54.0),
    "tachycardic": dict(bpm=136.0, systolic=118.0, diastolic=78.0),
    "bradycardic": dict(bpm=40.0, systolic=112.0, diastolic=74.0),
}

TRAJECTORY_MIX = {
    "normal": 0.40,
    "normal_with_artifact": 0.10,
    "hypertensive": 0.14,
    "hypotensive": 0.12,
    "tachycardic": 0.12,
    "bradycardic": 0.12,
}


def is_crisis(bpm: float, systolic: float, diastolic: float) -> bool:
    return bpm > 120 or bpm < 50 or systolic > 140 or diastolic > 90 or systolic < 90


def _stable_trajectory(rng: np.random.Generator) -> np.ndarray:
    out = np.zeros((T, 3))
    for i, name in enumerate(FEATURE_NAMES):
        out[:, i] = rng.normal(BASELINE[name], NOISE_STD[name], size=T)
    return out


def _drifting_trajectory(rng: np.random.Generator, target: dict) -> np.ndarray:
    onset = rng.integers(10, 26)
    out = np.zeros((T, 3))
    for i, name in enumerate(FEATURE_NAMES):
        baseline = BASELINE[name]
        goal = target[name]
        series = np.empty(T)
        series[:onset] = rng.normal(baseline, NOISE_STD[name], size=onset)
        remaining = T - onset
        ramp = np.linspace(0.0, 1.0, remaining) ** 1.3  # slightly non-linear onset
        drifted_mean = baseline + (goal - baseline) * ramp
        series[onset:] = drifted_mean + rng.normal(0.0, NOISE_STD[name] * 0.8, size=remaining)
        out[:, i] = series
    return out


def _normal_with_artifact(rng: np.random.Generator) -> np.ndarray:
    out = _stable_trajectory(rng)
    spike_t = rng.integers(8, T - 2)
    spike_len = rng.integers(1, 3)
    feature = rng.integers(0, 3)
    name = FEATURE_NAMES[feature]
    spike_value = TARGETS[rng.choice(list(TARGETS.keys()))][name]
    out[spike_t:spike_t + spike_len, feature] = spike_value + rng.normal(0, 2.0, size=min(spike_len, T - spike_t))
    return out


def make_trajectory(rng: np.random.Generator) -> tuple[np.ndarray, str]:
    kind = rng.choice(list(TRAJECTORY_MIX.keys()), p=list(TRAJECTORY_MIX.values()))
    if kind == "normal":
        return _stable_trajectory(rng), kind
    if kind == "normal_with_artifact":
        return _normal_with_artifact(rng), kind
    return _drifting_trajectory(rng, TARGETS[kind]), kind


def windows_from_trajectory(traj: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    features, labels = [], []
    for t in range(WINDOW_SIZE - 1, T - HORIZON):
        window = traj[t - WINDOW_SIZE + 1: t + 1]
        future = traj[t + 1: t + 1 + HORIZON]
        label = 1 if any(is_crisis(*row) for row in future) else 0
        features.append(window)
        labels.append(label)
    return np.stack(features), np.array(labels)


def build_dataset(n_trajectories: int = 400, seed: int = 7):
    rng = np.random.default_rng(seed)
    X_all, y_all, kinds_all = [], [], []
    for _ in range(n_trajectories):
        traj, kind = make_trajectory(rng)
        X, y = windows_from_trajectory(traj)
        X_all.append(X)
        y_all.append(y)
        kinds_all.extend([kind] * len(y))
    X_all = np.concatenate(X_all, axis=0)
    y_all = np.concatenate(y_all, axis=0)
    return X_all, y_all, np.array(kinds_all)


def train_test_split(X, y, kinds, test_frac=0.2, seed=11):
    rng = np.random.default_rng(seed)
    n = len(y)
    idx = rng.permutation(n)
    n_test = int(n * test_frac)
    test_idx, train_idx = idx[:n_test], idx[n_test:]
    return (X[train_idx], y[train_idx], kinds[train_idx]), (X[test_idx], y[test_idx], kinds[test_idx])


if __name__ == "__main__":
    X, y, kinds = build_dataset()
    print(f"Total windows: {len(y)}  |  positive rate: {y.mean():.3f}")
    for k in sorted(set(kinds)):
        mask = kinds == k
        print(f"  {k:22s} n={mask.sum():5d}  positive_rate={y[mask].mean():.3f}")
