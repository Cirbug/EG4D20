# EG4D20 handwritten digit CNN

The PC baseline treats a 320x180 grayscale frame as a set of digit blobs:
OpenCV finds the blobs, each crop is normalized to 28x28, and a small ten-class
CNN predicts `0` through `9`. The r6 FPGA build now performs the same main
stages in RTL: it thresholds dark ink on a bright background, locates candidate
boxes across the full frame, normalizes each candidate to 28x28, and reuses the
integer CNN sequentially. A frame can contain fewer than ten digits; the
detector reports each class and its box over UART.

## PC setup and MNIST baseline

Use Python 3.10 or newer. From `D:\2026fpga\EG4D20`:

```powershell
python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130
python -m pip install numpy opencv-python-headless Pillow
python cnn/train_digits.py --epochs 5
```

The first command uses the CUDA 13.0 PyTorch wheels. The tested PC has an RTX
4070 Laptop GPU and a CUDA 13.4-capable driver; the trainer automatically uses
CUDA when available and prints the selected device. On a CPU-only PC, install
the CPU build with `--index-url https://download.pytorch.org/whl/cpu` instead.
The package list is also recorded in `requirements.txt`.

The training command downloads MNIST from the Google-hosted dataset mirror with
torchvision's original MD5 checks, trains on its 60,000 training examples, and
reports accuracy on the separate 10,000-example MNIST test set. Data is stored
under `cnn/data/mnist`; the best checkpoint is
`cnn/checkpoints/digit_cnn_mnist.pt`.

Validated PC runs use the same network, five epochs, and batch size 128:

- PyTorch 2.14.1 CPU build: MNIST test accuracy 94.35%.
- PyTorch 2.14.1+cu130, CUDA runtime 13.0, RTX 4070 Laptop GPU (8 GB): MNIST
  test accuracy 94.34%. CUDA detection and a GPU matrix multiplication both
  passed.

The CUDA checkpoint is `cnn/checkpoints/digit_cnn_mnist_cuda.pt`; the CPU
reference remains `cnn/checkpoints/digit_cnn_mnist.pt`. The verified CUDA
environment for this PC is `%TEMP%\eg4d20-cnn-venv`. Training automatically
selects CUDA when a CUDA-enabled PyTorch build is installed.

Convert camera images to grayscale 320x180 PNGs before segmentation:

```powershell
python cnn/prepare_frames.py photo --output-dir cnn/outputs/photo_320x180_gray
```

The script accepts one image or a directory (including subdirectories), keeps
the 16:9 aspect ratio by center-cropping other input ratios, and does not add
black borders. Existing outputs are skipped unless `--overwrite` is supplied.
The 13 1920x1080 screenshots currently in `photo` already match 16:9, so they are
resized directly and converted to single-channel 8-bit PNGs.

The same converter supports selectable output color and geometry:

```powershell
# RGB 320x180, preserving aspect ratio by center crop
python cnn/prepare_frames.py photo/2026.10.17 --color rgb --transform fit --format png --output-dir cnn/outputs/frames_rgb

# Grayscale 320x180 with direct stretch (no crop)
python cnn/prepare_frames.py photo/2026.10.17 --color gray --transform stretch --format png --output-dir cnn/outputs/frames_stretch

# Keep the original resolution, only convert to RGB JPEG
python cnn/prepare_frames.py photo/2026.10.17 --color rgb --transform none --format jpg --output-dir cnn/outputs/frames_original_rgb
```

`--color gray --transform fit` is the only form accepted by the current
`send_cnn_image.py` UDP path. RGB or original-size outputs are for inspection,
manual annotation, or PC processing until a matching FPGA input protocol is
implemented.

For manually labeled Pascal VOC XML files, crop each digit without shrinking
the whole frame first:

```powershell
python cnn/crop_annotated_digits.py "photo/2026.10.17/Screenshot 2026-10-27 12-34-17.xml" `
  --output-dir cnn/outputs/annotated_digits --margin 8 --size 28
```

This writes a source-resolution crop and an optional centered `28x28` crop for
each labeled box, grouped by label, plus `manifest.json`.

The project also includes the public MNIST IDX files under `cnn/data/mnist`.
They can be composed into full-frame detection samples without downloading
anything again:

```powershell
python cnn/make_mnist_frames.py `
  --output-dir cnn/outputs/mnist_frames_320x180 `
  --count 200 --digits-per-frame 10 --binary
```

Digits are composed on a `1920x1080` canvas and reduced using 6x6 box averaging
to match the main-board preprocessing. With `--binary`, source strokes are
thresholded before averaging, so edge pixels in the output can have gray
coverage values. Each `320x180` PNG has a matching Pascal VOC XML file with
digit labels and boxes. These synthetic samples validate the full-frame data
path and detector plumbing; they do not replace camera-domain samples for final
accuracy evaluation.

To segment the supplied OBS frame and inspect every crop:

```powershell
python cnn/segment_digits.py xuniji/ph1p35_obs_frame_320x180_gray.png --expect 10
```

The default ROI is `24,38,296,112` for the supplied 320x180 OBS frame, which
excludes the camera/status overlays. Pass `--roi x,y,width,height` for another
capture or crop. The default output is `cnn/outputs/digit_segmentation/`. It
contains a binary mask, a numbered contact sheet, one 28x28 PNG per detected
digit, and a JSON manifest with source-image bounding boxes ordered top-to-
bottom and left-to-right. A nonempty output directory is never overwritten;
pass a new `--output` path on reruns.

Run the MNIST checkpoint against a frame:

```powershell
python cnn/predict_digits.py xuniji/ph1p35_obs_frame_320x180_gray.png --expect 10
```

The prediction sheet and per-digit confidence values go to
`cnn/outputs/digit_predictions/`. MNIST accuracy is not camera accuracy. The
OBS frame has only one example of each digit and is useful for checking the
segmentation and spotting domain mismatch, not for training or a reliable
accuracy claim. Future target images are expected to contain much less OBS, so
use clean target captures as the primary training and evaluation data. Keep a
smaller set of OBS/menu-heavy frames for clutter and false-detection checks.
Collect labeled clean captures from separate sessions before reporting
target-domain accuracy. On the supplied single frame, both CPU and
CUDA checkpoints predicted `0123456784` instead of `0123456789`; the last
handwritten `9` was misclassified as `4`. The CUDA confidence for that `4` was
0.522. CUDA predictions are in `cnn/outputs/digit_predictions_cuda/`. This is a
one-frame smoke test, not a camera accuracy estimate.

For a separate camera adaptation experiment, pass segmented frame directories
to `train_camera_adapt.py`. Crop index `00` is labeled `0`, through crop `09`
labeled `9`; every supplied frame must contain the digits in that order. Keep
training and evaluation source images disjoint. The script fine-tunes a copy of
the MNIST checkpoint, reports both camera-set and MNIST-test accuracy, and
refuses to overwrite an existing checkpoint:

```powershell
python cnn/train_camera_adapt.py `
  --train-dirs cnn/outputs/photo_digits_320x180/<training-frame-1> cnn/outputs/photo_digits_320x180/<training-frame-2> `
  --eval-dirs cnn/outputs/photo_digits_320x180/<held-out-frame-1> cnn/outputs/photo_digits_320x180/<held-out-frame-2> `
  --output cnn/checkpoints/digit_cnn_camera_adapt.pt
```

This is a PC-side experiment. Its held-out score only estimates generalization
to the supplied capture group; collect more writers and sessions before
claiming reliable recognition or exporting weights to RTL.

2026-10-26 camera experiment: five earlier frames (50 crops) were used for
fine-tuning and eight later frames (80 crops) were held out. The MNIST
checkpoint got 45/80 on those later frames; the adapted checkpoint got 50/80
(62.5%). MNIST test accuracy changed from 94.34% to 93.45%. The result is
preliminary because the eight frames come from a small number of capture
sessions and include near-duplicate views. The generated checkpoint is
`cnn/checkpoints/digit_cnn_camera_adapt_20261026.pt`. One frame needed a higher
ROI top edge (`20,16,300,140`) because its digits were near the top of the image.

## Network and hardware boundary

`digit_model.py` defines three 3x3 convolution layers with 8/16/16 channels,
ReLU and 2x2 max pooling, followed by global average pooling and a 10-logit
classifier. Its input is a centered 28x28 grayscale digit, normalized to
0..1, with bright ink on a dark background to match MNIST.

| Stage | Output |
| --- | --- |
| Input | 1 x 28 x 28 |
| Conv 1->8 + pool | 8 x 14 x 14 |
| Conv 8->16 + pool | 16 x 7 x 7 |
| Conv 16->16 + pool | 16 x 3 x 3 |
| Global average + linear | 10 logits |

The model has 3,738 trainable parameters and about 0.40 million convolution
MACs per digit. These are software architecture counts, not an FPGA resource or
timing result. The EG4D20 has 29 DSPs; a hardware version still needs a frame
ROI/connected-component stage, fixed-point quantization, a reused MAC datapath,
DDR/BRAM scheduling, and bit-exact RTL comparison against a software reference.
Do not load this floating-point checkpoint directly into FPGA fabric.

The routed r6 build uses the camera-adapted checkpoint
`cnn/checkpoints/digit_cnn_camera_adapt_20261026.pt`, top `cnn_image_detect_top`,
and produces
`D:\2026fpga\bank\eg4d20_cnn_detect_20261027_r6_ramfix3\fpga\eg4d20_cnn_detect.bit`.
It uses 10,621/19,600 LUTs (54.19%), 6,624/19,600 registers (33.80%),
43/64 BRAM9K, 9/16 BRAM32K, 6/29 DSPs, and 3/4 PLLs. Routed setup WNS is
+0.108 ns and hold WNS is +0.004 ns with 99.62% STA coverage; timing passes,
but the hold margin is small.

The camera-adapted checkpoint reached 62.5% PC accuracy on 80 held-out crops
from separate camera captures. In full-frame RTL simulation, the detector found
all ten annotated boxes in `cnn/outputs/verify_frames_osd_light/`, while the
quantized CNN got 4/10 classes right (`0,1,5,5,8,9,6,4,8,2`). That screenshot
uses a different handwriting/image domain from the camera training set, so this
single-frame result is a stress test rather than an estimate for future clean
camera frames. The RTL flow has not yet been validated on the physical EG4D20;
the next hardware check is to program r6, send a clean 320x180 grayscale frame,
and compare UART boxes/classes with its labels.

Run the all-digit full-frame RTL test with:

```powershell
python tests/run_cnn_frame_digit_detector_rtl.py --real-cnn --all-digits
```

The former full-frame binary experiment remains in `model.py` and
`train_binary_cnn.py` for reference. It is not the handwritten digit model.

## FPGA references

Local EG4D20 DDR and network examples are documented in the project root
`README.txt`, under `D:\2026fpga\.DOC\01_F01_FC01_EG4D`. CNN architecture examples
that informed the low-resource direction:

- [FPGA 8-bit Quantized CNN Accelerator](https://github.com/m-kvlk/FPGA-8bit-Quantized-CNN-Accelerator): MAX10/DE10-Lite, sequential FSM and reused 8-bit MACs.
- [FINN](https://github.com/Xilinx/finn): quantized streaming accelerator; primarily an AMD/Xilinx flow.
- [hls4ml](https://github.com/fastmachinelearning/hls4ml): quantization and small-CNN examples; not a direct Anlogic TD bitstream flow.

These are architecture references. None is a drop-in EG4D20/TD CNN implementation.
