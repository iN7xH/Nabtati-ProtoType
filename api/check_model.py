"""
check_model.py - test the real model WITHOUT starting the server or the app.

Usage (inside the real-mode venv, from the api/ folder):
    python check_model.py path/to/leaf1.jpg path/to/leaf2.jpg ...

Use photos whose correct label you KNOW (e.g. from your validation set).
If the predictions are right with high confidence -> PREPROCESSING is correct.
If they are wrong or all low confidence -> try another PREPROCESSING value in predictor.py
(or set it for one run:  $env:PREPROCESSING="rescale_-1_1"  in PowerShell).
"""

import sys
from pathlib import Path

from predictor import PREPROCESSING, Predictor


def main() -> None:
    images = sys.argv[1:]
    if not images:
        print(__doc__)
        sys.exit(1)

    predictor = Predictor(mode="real")  # always real mode, whatever MODEL_MODE says
    predictor.load()

    print(f"\npreprocessing = '{PREPROCESSING}', input size = {predictor.image_size}\n")
    for path in images:
        results = predictor.predict(Path(path).read_bytes())
        print(Path(path).name)
        for label, conf in results[:3]:
            print(f"    {conf:6.1%}  {label}")
        print()


if __name__ == "__main__":
    main()
