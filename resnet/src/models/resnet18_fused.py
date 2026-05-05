import torch.nn as nn
import torch.nn.functional as F


class BasicBlockFused(nn.Module):
    """BasicBlock with BN folded into conv biases (inference-only)."""

    def __init__(self, in_ch, out_ch, stride=1):
        super().__init__()
        self.conv1 = nn.Conv2d(in_ch, out_ch, 3, stride=stride, padding=1, bias=True)
        self.conv2 = nn.Conv2d(out_ch, out_ch, 3, padding=1, bias=True)
        if stride != 1 or in_ch != out_ch:
            self.shortcut = nn.Conv2d(in_ch, out_ch, 1, stride=stride, bias=True)

    def forward(self, x):
        residual = self.shortcut(x) if hasattr(self, 'shortcut') else x
        out = F.relu(self.conv1(x))
        out = self.conv2(out)
        return F.relu(out + residual)


class ResNet18Fused(nn.Module):
    """ResNet-18 CIFAR variant with BatchNorm folded in — matches the C++ posit model parameter layout."""

    def __init__(self, num_classes=10):
        super().__init__()
        self.stem = nn.Conv2d(3, 64, 3, stride=1, padding=1, bias=True)
        self.layer1 = nn.Sequential(BasicBlockFused(64, 64), BasicBlockFused(64, 64))
        self.layer2 = nn.Sequential(BasicBlockFused(64, 128, 2), BasicBlockFused(128, 128))
        self.layer3 = nn.Sequential(BasicBlockFused(128, 256, 2), BasicBlockFused(256, 256))
        self.layer4 = nn.Sequential(BasicBlockFused(256, 512, 2), BasicBlockFused(512, 512))
        self.fc = nn.Linear(512, num_classes)

    def forward(self, x):
        x = F.relu(self.stem(x))
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        x = x.mean([2, 3])
        return self.fc(x)
