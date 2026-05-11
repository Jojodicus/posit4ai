"""SmallNet: one-hidden-layer FC network for MNIST.

Architecture: Flatten -> Linear(784, 32) -> ReLU -> Linear(32, 10)

Parameter layout (matches SmallNetPosit in cpp/include/smallnet.hpp):
  fc1 weight (32x784), fc1 bias (32), fc2 weight (10x32), fc2 bias (10)
"""
import torch.nn as nn

HIDDEN_NEURONS = 32

class SmallNet(nn.Module):
    def __init__(self, num_classes: int = 10):
        super().__init__()
        self.fc1 = nn.Linear(784, HIDDEN_NEURONS)
        self.fc2 = nn.Linear(HIDDEN_NEURONS, num_classes)
        self.relu = nn.ReLU(inplace=True)

    def forward(self, x):
        x = x.view(x.size(0), -1)
        x = self.relu(self.fc1(x))
        return self.fc2(x)
