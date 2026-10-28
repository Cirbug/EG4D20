"""Small grayscale binary CNN shared by training and checkpoint export."""

from torch import nn
from torch.nn import functional as F

if __package__:
    from .image_preprocess import INPUT_HEIGHT, INPUT_WIDTH
else:
    from image_preprocess import INPUT_HEIGHT, INPUT_WIDTH

CLASS_COUNT = 2


class SmallBinaryCNN(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, kernel_size=3, padding=1, bias=True)
        self.conv2 = nn.Conv2d(8, 16, kernel_size=3, padding=1, bias=True)
        self.conv3 = nn.Conv2d(16, 16, kernel_size=3, padding=1, bias=True)
        self.classifier = nn.Linear(16, CLASS_COUNT, bias=True)

    def forward_features(self, image):
        image = F.max_pool2d(F.relu(self.conv1(image)), kernel_size=2)
        image = F.max_pool2d(F.relu(self.conv2(image)), kernel_size=2)
        image = F.max_pool2d(F.relu(self.conv3(image)), kernel_size=2)
        return image

    def forward(self, image):
        features = self.forward_features(image)
        pooled = features.mean(dim=(2, 3))
        return self.classifier(pooled)
