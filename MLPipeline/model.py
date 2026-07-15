"""
model.py

PyTorch definition of the CardioGuard on-device early-warning model.
Mirrors the architecture validated in reference_validation/numpy_reference.py:
    18 (6 readings x [bpm, systolic, diastolic]) -> Dense(h1, ReLU)
    -> Dense(h2, ReLU) -> Dense(1, Sigmoid)

Normalization (mean/std) is registered as a model buffer and applied inside
forward(), so the exported Core ML model accepts raw vitals directly - the
Swift integration (CoreMLCardioRiskPredictor.swift) does not need to
replicate any preprocessing logic.
"""
import torch
import torch.nn as nn


class CardioRiskNet(nn.Module):
    def __init__(self, hidden1: int = 16, hidden2: int = 8, mean=None, std=None):
        super().__init__()
        self.fc1 = nn.Linear(18, hidden1)
        self.fc2 = nn.Linear(hidden1, hidden2)
        self.fc3 = nn.Linear(hidden2, 1)
        self.relu = nn.ReLU()

        mean_t = torch.zeros(18) if mean is None else torch.tensor(mean, dtype=torch.float32)
        std_t = torch.ones(18) if std is None else torch.tensor(std, dtype=torch.float32)
        self.register_buffer("mean", mean_t)
        self.register_buffer("std", std_t)

    def forward(self, readings: torch.Tensor) -> torch.Tensor:
        # readings: (batch, 6, 3) raw vitals (bpm, systolic, diastolic)
        x = readings.flatten(start_dim=1)
        x = (x - self.mean) / self.std
        x = self.relu(self.fc1(x))
        x = self.relu(self.fc2(x))
        x = torch.sigmoid(self.fc3(x))
        return x

    def param_count(self) -> int:
        return sum(p.numel() for p in self.parameters())
