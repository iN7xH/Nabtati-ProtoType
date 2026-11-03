"""
predictor.py - the ONLY file that changes when the real model is plugged in.

Two modes, chosen with the environment variable MODEL_MODE:
  MODEL_MODE=mock  (default)  -> random but plausible prediction. No ML libraries needed.
  MODEL_MODE=real             -> loads model.keras + labels.txt and runs the real model.

Most things are detected automatically from the model (input size, softmax, number of classes).
The ONE thing that must match training is PREPROCESSING below.

Public interface used by main.py (do NOT change it):
  p = Predictor(); p.load()
  p.predict(image_bytes) -> [(label, confidence), ...] for all labels, highest first
  p.mode -> "mock" | "real"        p.model_loaded -> bool
  split_label("tomato__late_blight") -> ("tomato", "late_blight")
"""

import io
import os
import random
import re
from pathlib import Path

from PIL import Image, ImageOps

API_DIR = Path(__file__).parent


# =====================================================================================
# TEAMMATE: SETTINGS - edit only this block (or override each with an environment variable)
# =====================================================================================

# How pixels were scaled in TRAINING. Pick the option that matches your training code:
#   "none"         model already contains its own preprocessing, e.g. a Rescaling layer,
#                  or EfficientNet / MobileNetV3 / ConvNeXt from keras.applications
#                  (they expect raw 0-255 pixels)
#   "rescale_0_1"  you did x / 255  (or Rescaling(1./255) OUTSIDE the saved model)
#   "rescale_-1_1" you did x / 127.5 - 1  (= mobilenet_v2 / inception_v3 / xception preprocess_input)
#   "caffe"        resnet50 / vgg16 / vgg19 preprocess_input (RGB->BGR + ImageNet mean subtraction)
# TODO (teammate): CONFIRM THIS. Verify with:  python check_model.py <leaf image with known label>
PREPROCESSING = os.getenv("PREPROCESSING", "rescale_0_1")

# Input size (height, width). None = read it from the model automatically (recommended).
# TODO (teammate): only set this if the model has no fixed input size, e.g. (224, 224).
IMAGE_SIZE = None

# Model file. model.keras is used if present, otherwise model.h5.
MODEL_PATH = Path(os.getenv("MODEL_PATH", API_DIR / "model.keras"))
LABELS_PATH = Path(os.getenv("LABELS_PATH", API_DIR / "labels.txt"))

# =====================================================================================
# Everything below works as-is. No changes needed.
# =====================================================================================

DEFAULT_IMAGE_SIZE = (224, 224)

# The 19 classes agreed for the project (CLAUDE.md). Only used to WARN about unexpected labels.
KNOWN_LABELS = {
    "tomato__healthy", "tomato__early_blight", "tomato__late_blight", "tomato__bacterial_spot",
    "tomato__septoria_leaf_spot", "tomato__leaf_mold", "tomato__yellow_leaf_curl_virus",
    "tomato__mosaic_virus", "tomato__spider_mites", "tomato__target_spot",
    "potato__healthy", "potato__early_blight", "potato__late_blight",
    "pepper__healthy", "pepper__bacterial_spot",
    "cucumber__healthy", "cucumber__downy_mildew", "cucumber__gummy_stem_blight",
    "cucumber__anthracnose",
}


def normalize_label(raw: str) -> str:
    """Make labels consistent: 'Tomato___Late blight' -> 'tomato__late_blight'.

    Crop and disease are separated by 2+ underscores; inside each part, any run of
    spaces/punctuation becomes a single '_'.
    """
    parts = re.split(r"_{2,}", raw.strip().lower(), maxsplit=1)
    if len(parts) != 2:
        raise ValueError(
            f"Label '{raw}' must look like crop__disease (two underscores), e.g. tomato__late_blight"
        )
    crop, disease = (re.sub(r"[^a-z0-9]+", "_", p).strip("_") for p in parts)
    if not crop or not disease:
        raise ValueError(f"Label '{raw}' has an empty crop or disease part")
    return f"{crop}__{disease}"


def split_label(label: str) -> tuple[str, str]:
    """'tomato__late_blight' -> ('tomato', 'late_blight')"""
    crop, disease = label.split("__", 1)
    return crop, disease


def load_labels(path: Path = LABELS_PATH) -> list[str]:
    """Read labels.txt: one label per line, in the SAME order as the model's output neurons.

    utf-8-sig ignores a BOM (added by some Windows editors); blank lines are skipped.
    """
    with open(path, encoding="utf-8-sig") as f:
        labels = [normalize_label(line) for line in f if line.strip()]
    if len(set(labels)) != len(labels):
        raise ValueError(f"{path.name} contains duplicate labels")
    return labels


class Predictor:
    def __init__(self, mode: str | None = None):
        self.mode = (mode or os.getenv("MODEL_MODE", "mock")).strip().lower()
        if self.mode not in ("mock", "real"):
            raise ValueError(f"MODEL_MODE must be 'mock' or 'real', got '{self.mode}'")
        self.labels = load_labels()
        self.model = None
        self.model_loaded = False
        self.image_size = IMAGE_SIZE or DEFAULT_IMAGE_SIZE

    # ------------------------------------------------------------------ load
    def load(self) -> None:
        """Called once when the API starts. In real mode, fails fast with a clear message."""
        unknown = [l for l in self.labels if l not in KNOWN_LABELS]
        if unknown:
            print(f"[predictor] WARNING: labels not in the agreed 19-class list: {unknown}")

        if self.mode == "mock":
            return  # nothing to load; model_loaded stays False so /health is honest

        if PREPROCESSING not in _PREPROCESSORS:
            raise ValueError(
                f"PREPROCESSING='{PREPROCESSING}' is not one of {list(_PREPROCESSORS)}"
            )

        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")  # hide TensorFlow's noisy C++ info logs
        try:
            import tensorflow as tf  # imported here so mock mode doesn't need TensorFlow
        except ImportError as exc:
            raise RuntimeError(
                "MODEL_MODE=real needs TensorFlow. Use the real-mode venv: "
                "pip install -r requirements-real.txt (see README)."
            ) from exc

        model_path = MODEL_PATH
        if not model_path.exists() and model_path.with_suffix(".h5").exists():
            model_path = model_path.with_suffix(".h5")
        if not model_path.exists():
            raise FileNotFoundError(f"Model file not found: {model_path} (put model.keras in api/)")

        print(f"[predictor] loading {model_path.name} ...")
        self.model = tf.keras.models.load_model(model_path, compile=False)

        # Number of outputs must equal number of labels.
        n_outputs = self.model.output_shape[-1]
        if n_outputs != len(self.labels):
            raise ValueError(
                f"Model has {n_outputs} outputs but {LABELS_PATH.name} has {len(self.labels)} labels"
            )

        # Input size: read from the model, e.g. input_shape = (None, 224, 224, 3).
        if IMAGE_SIZE is None:
            h, w = self.model.input_shape[1:3]
            if h and w:
                self.image_size = (int(h), int(w))

        # Warm-up: the first call is slow (graph building); do it now, not on the user's request.
        self._real_scores(Image.new("RGB", self.image_size))
        self.model_loaded = True
        print(
            f"[predictor] ready: {len(self.labels)} classes, input {self.image_size}, "
            f"preprocessing='{PREPROCESSING}'"
        )

    # --------------------------------------------------------------- predict
    def predict(self, image_bytes: bytes) -> list[tuple[str, float]]:
        """Return [(label, confidence), ...] for ALL labels, highest first."""
        image = Image.open(io.BytesIO(image_bytes))
        image = ImageOps.exif_transpose(image)  # phone photos: apply EXIF rotation
        image = image.convert("RGB")  # drop alpha (PNG), grayscale -> 3 channels

        scores = self._real_scores(image) if self.mode == "real" else self._mock_scores()

        pairs = list(zip(self.labels, scores))
        pairs.sort(key=lambda p: p[1], reverse=True)
        return pairs

    # ----------------------------------------------------------- mock helper
    def _mock_scores(self) -> list[float]:
        """Fake softmax output: one random label gets 0.55-0.98, the rest share the remainder.
        Sometimes below 0.70 so the app's "Not sure" message can be tested."""
        n = len(self.labels)
        winner = random.randrange(n)
        top = random.uniform(0.55, 0.98)
        rest = [random.random() for _ in range(n - 1)]
        total = sum(rest)
        rest = [r / total * (1 - top) for r in rest]
        return rest[:winner] + [top] + rest[winner:]

    # ----------------------------------------------------------- real helper
    def _real_scores(self, image: Image.Image) -> list[float]:
        import numpy as np

        h, w = self.image_size
        image = image.resize((w, h), Image.BILINEAR)  # PIL takes (width, height)
        x = np.asarray(image, dtype=np.float32)  # (h, w, 3), values 0-255
        x = np.asarray(_PREPROCESSORS[PREPROCESSING](x), dtype=np.float32)
        x = np.expand_dims(x, axis=0)  # batch of 1 -> (1, h, w, 3)

        out = self.model(x, training=False)
        if isinstance(out, (list, tuple)):  # models with several outputs: use the first
            out = out[0]
        probs = np.asarray(out, dtype=np.float64).reshape(-1)

        # If the last layer had no softmax (raw logits), apply it here.
        if probs.min() < 0 or abs(probs.sum() - 1.0) > 1e-3:
            e = np.exp(probs - probs.max())
            probs = e / e.sum()

        return [float(p) for p in probs]


# Preprocessing functions: input = float32 array (h, w, 3) RGB 0-255.
def _caffe(x):
    x = x[..., ::-1]  # RGB -> BGR
    return x - [103.939, 116.779, 123.68]


_PREPROCESSORS = {
    "none": lambda x: x,
    "rescale_0_1": lambda x: x / 255.0,
    "rescale_-1_1": lambda x: x / 127.5 - 1.0,
    "caffe": _caffe,
}
