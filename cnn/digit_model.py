"""Small 28x28 grayscale CNN for ten-way handwritten digit classification."""

from torch import nn
from torch.nn import functional as F


INPUT_SIZE = 28
CLASSES = tuple(str(digit) for digit in range(10))


class SmallDigitCNN(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, kernel_size=3, padding=1, bias=True)
        self.conv2 = nn.Conv2d(8, 16, kernel_size=3, padding=1, bias=True)
        self.conv3 = nn.Conv2d(16, 16, kernel_size=3, padding=1, bias=True)
        self.classifier = nn.Linear(16, len(CLASSES), bias=True)

    def forward_features(self, image):
        image = F.max_pool2d(F.relu(self.conv1(image)), kernel_size=2)
        image = F.max_pool2d(F.relu(self.conv2(image)), kernel_size=2)
        image = F.max_pool2d(F.relu(self.conv3(image)), kernel_size=2)
        return image

    def forward(self, image):
        features = self.forward_features(image)
        return self.classifier(features.mean(dim=(2, 3)))
