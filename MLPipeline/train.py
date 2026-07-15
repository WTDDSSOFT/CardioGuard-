"""
train.py

Trains the baseline CardioRiskNet on the synthetic dataset from
generate_data.py, evaluates it on a held-out split, and saves:
  - cardio_risk_predictor.pt (state_dict + normalization buffers)
  - train_report.json (accuracy / precision / recall / F1)

Run: python train.py
Requires: torch, numpy  (see requirements.txt)
"""
import json

import numpy as np
import torch
import torch.nn as nn

from generate_data import build_dataset, train_test_split
from model import CardioRiskNet

SEED = 1
torch.manual_seed(SEED)


def to_tensor(x, dtype=torch.float32):
    return torch.tensor(x, dtype=dtype)


def evaluate(model, X, y, threshold=0.5):
    model.eval()
    with torch.no_grad():
        p = model(X).reshape(-1)
    pred = (p >= threshold).int()
    y_int = y.int()
    tp = int(((pred == 1) & (y_int == 1)).sum())
    fp = int(((pred == 1) & (y_int == 0)).sum())
    fn = int(((pred == 0) & (y_int == 1)).sum())
    tn = int(((pred == 0) & (y_int == 0)).sum())
    accuracy = (tp + tn) / len(y)
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    return dict(accuracy=accuracy, precision=precision, recall=recall, f1=f1,
                tp=tp, fp=fp, fn=fn, tn=tn)


def main():
    X, y, kinds = build_dataset(n_trajectories=400, seed=7)
    (X_train, y_train, _), (X_test, y_test, _) = train_test_split(X, y, kinds)

    flat = X_train.reshape(len(X_train), -1)
    mean, std = flat.mean(axis=0), flat.std(axis=0) + 1e-6

    model = CardioRiskNet(hidden1=16, hidden2=8, mean=mean, std=std)

    pos_weight = torch.tensor([(y_train == 0).sum() / max((y_train == 1).sum(), 1)])
    criterion = nn.BCELoss(reduction="none")
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01)

    X_train_t = to_tensor(X_train)
    y_train_t = to_tensor(y_train)
    X_test_t = to_tensor(X_test)
    y_test_t = to_tensor(y_test)

    n = len(y_train)
    batch_size = 64
    epochs = 80

    model.train()
    for epoch in range(epochs):
        perm = torch.randperm(n)
        for start in range(0, n, batch_size):
            idx = perm[start:start + batch_size]
            optimizer.zero_grad()
            out = model(X_train_t[idx]).reshape(-1)
            weights = torch.where(y_train_t[idx] == 1, pos_weight, torch.tensor(1.0))
            loss = (criterion(out, y_train_t[idx]) * weights).mean()
            loss.backward()
            optimizer.step()

    metrics = evaluate(model, X_test_t, y_test_t)
    print("Baseline test metrics:", json.dumps(metrics, indent=2))
    print("Param count:", model.param_count())

    torch.save({"state_dict": model.state_dict(), "hidden1": 16, "hidden2": 8}, "cardio_risk_predictor.pt")
    np.savez("normalization.npz", mean=mean, std=std)
    with open("train_report.json", "w") as f:
        json.dump({"metrics": metrics, "param_count": model.param_count()}, f, indent=2)


if __name__ == "__main__":
    main()
