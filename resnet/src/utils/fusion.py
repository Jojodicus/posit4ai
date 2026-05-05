import sys
from pathlib import Path

import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).parent.parent))
from models.resnet18 import ResNet18
from models.resnet18_fused import ResNet18Fused


def _fuse_conv_bn(conv: nn.Conv2d, bn: nn.BatchNorm2d) -> nn.Conv2d:
    scale = bn.weight / torch.sqrt(bn.running_var + bn.eps)
    w = conv.weight * scale.view(-1, 1, 1, 1)
    b = bn.bias - bn.running_mean * scale
    if conv.bias is not None:
        b = b + conv.bias * scale

    fused = nn.Conv2d(
        conv.in_channels, conv.out_channels, conv.kernel_size,
        stride=conv.stride, padding=conv.padding, bias=True,
    )
    fused.weight.data = w.detach()
    fused.bias.data = b.detach()
    return fused


def fold_resnet18(model: ResNet18, num_classes: int = 10) -> ResNet18Fused:
    """Fold BatchNorm parameters into preceding Conv2d for inference.

    The returned model's parameter() ordering matches the C++ posit ResNet18,
    enabling direct use with copy_parameters().
    """
    model.eval()
    fused = ResNet18Fused(num_classes)

    # stem: Sequential(Conv2d, BN2d, ReLU) -> single Conv2d
    fused.stem = _fuse_conv_bn(model.stem[0], model.stem[1])

    for layer_name in ('layer1', 'layer2', 'layer3', 'layer4'):
        for src_block, dst_block in zip(getattr(model, layer_name), getattr(fused, layer_name)):
            dst_block.conv1 = _fuse_conv_bn(src_block.net[0], src_block.net[1])
            dst_block.conv2 = _fuse_conv_bn(src_block.net[3], src_block.net[4])
            if hasattr(dst_block, 'shortcut'):
                dst_block.shortcut = _fuse_conv_bn(src_block.shortcut[0], src_block.shortcut[1])

    fused.fc.weight.data = model.fc.weight.data.detach().clone()
    fused.fc.bias.data = model.fc.bias.data.detach().clone()

    return fused


def export_fused_jit(model: ResNet18, path: Path) -> None:
    """Export BN-fused model as TorchScript for C++ posit inference."""
    dtype = next(model.parameters()).dtype
    fused = fold_resnet18(model).to(dtype).eval()
    dummy = torch.zeros(1, 3, 32, 32, dtype=dtype)
    with torch.no_grad():
        scripted = torch.jit.trace(fused.cpu(), dummy.cpu())
    torch.jit.save(scripted, str(path))
