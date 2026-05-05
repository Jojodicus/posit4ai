import torch.nn as nn
import torch.nn.functional as F


class CifarNet(nn.Module):
    """Small conv-net for CIFAR-10.

    Architecture matches positnn's CifarNet_posit so named_parameters() order
    is identical: conv1, conv2, fc1, fc2, fc3 (10 tensors total).
    """

    def __init__(self, num_classes=10):
        super().__init__()
        self.conv1 = nn.Conv2d(3, 8, 5, padding=2)
        self.conv2 = nn.Conv2d(8, 16, 5, padding=2)
        self.fc1 = nn.Linear(1024, 384)
        self.fc2 = nn.Linear(384, 192)
        self.fc3 = nn.Linear(192, num_classes)

    def forward(self, x):
        x = F.relu(F.max_pool2d(self.conv1(x), 2))
        x = F.relu(F.max_pool2d(self.conv2(x), 2))
        x = x.view(x.size(0), -1)
        x = F.relu(F.dropout(self.fc1(x), p=0.5, training=self.training))
        x = F.relu(F.dropout(self.fc2(x), p=0.5, training=self.training))
        return self.fc3(x)
