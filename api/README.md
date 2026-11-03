# Plant Disease Detection API (FastAPI)

The Flutter app sends a leaf photo to this API and shows the crop, the disease (or Healthy) and the confidence.

- **Mock mode** (default): returns a random prediction, so the app works before the model exists.
- **Real mode**: runs the trained Keras model.

Switching to real mode needs **no changes to `main.py` or to the Flutter app**. See
[Plugging in the real model](#plugging-in-the-real-model).

---

## Quick start (mock mode)

Windows PowerShell, from the `api/` folder:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

- If `Activate.ps1` is blocked, run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once.
- `--host 0.0.0.0` lets a real phone on the same Wi-Fi reach the API.
- Test it in Swagger at http://localhost:8000/docs (`POST /predict` → **Try it out** → choose an image → **Execute**), or with curl:
  ```powershell
  curl.exe http://localhost:8000/health
  curl.exe -F "image=@C:\path\to\leaf.jpg" http://localhost:8000/predict
  ```

---

## Plugging in the real model

You need **3 files** and **1 setting**:

| What | Where |
|---|---|
| `model.keras` (your trained model) | `api/model.keras` |
| `labels.txt` (your class names, in output order) | `api/labels.txt`, replacing the existing one |
| `PREPROCESSING` (how pixels were scaled in training) | top of `api/predictor.py` |
| `MODEL_MODE=real` | environment variable, set when you start the server |

### Step 1: Create a real-mode Python environment

TensorFlow does **not** support Python 3.14. Use **Python 3.10–3.12**, ideally the version you trained with.

```powershell
cd api
py -3.11 -m venv .venv-real          # or: py -3.12 -m venv .venv-real
.\.venv-real\Scripts\Activate.ps1
pip install -r requirements-real.txt
```

If you trained with a specific TensorFlow version (check `tf.__version__` in your notebook), install
that exact version, e.g. `pip install tensorflow==2.19.0`. A `.keras` file saved with a newer
TensorFlow/Keras than the one installed here may fail to load.

### Step 2: Export and copy the model

In your training notebook:

```python
model.save("model.keras")   # Keras 3 format (TF >= 2.16)
```

Copy `model.keras` into the `api/` folder. (`model.h5` also works if that is all you have.
An old SavedModel *folder* does not, so re-save it as `.keras`.)

### Step 3: Create `labels.txt` in the model's output order

**This is the most common mistake.** Line 1 of `labels.txt` must be the class of output neuron 0,
line 2 of neuron 1, and so on. If you trained with `image_dataset_from_directory` or
`flow_from_directory`, the order is **alphabetical by folder name**, not the order listed in CLAUDE.md.
Generate the file from your training code instead of typing it:

```python
# image_dataset_from_directory:
class_names = train_ds.class_names
# flow_from_directory / ImageDataGenerator:
# class_names = sorted(train_gen.class_indices, key=train_gen.class_indices.get)

with open("labels.txt", "w") as f:
    f.write("\n".join(class_names))
```

Format of each line: `crop__disease`, with **two underscores** between crop and disease, e.g. `tomato__late_blight`.

- Healthy classes must have `healthy` as the disease (`tomato__healthy`), because the app uses that to show "Healthy".
- PlantVillage-style names are cleaned up automatically: `Tomato___Late_blight` → `tomato__late_blight`.
- When the server starts, it prints a **WARNING** for any label that is not one of the 19 agreed
  classes (e.g. `pepper_bell__bacterial_spot` instead of `pepper__bacterial_spot`). Everything still
  works, but rename those lines so the app shows the agreed names.
- The server refuses to start if the number of labels ≠ the number of model outputs.

### Step 4: Set `PREPROCESSING` in `predictor.py`

At the top of `predictor.py` (the only place to edit):

```python
PREPROCESSING = os.getenv("PREPROCESSING", "rescale_0_1")   # <- change "rescale_0_1"
```

Pick the option that matches **what your training code did to the pixels**:

| Your training code | Value |
|---|---|
| `Rescaling(1./255)` layer **inside** the saved model | `"none"` |
| `EfficientNet*`, `MobileNetV3*`, `ConvNeXt*` from `keras.applications` | `"none"` |
| `x / 255.0`, `ImageDataGenerator(rescale=1./255)`, or a Rescaling layer **outside** the saved model | `"rescale_0_1"` |
| `mobilenet_v2.preprocess_input`, `inception_v3` / `xception` preprocess, or `x / 127.5 - 1` | `"rescale_-1_1"` |
| `resnet50`, `vgg16`, `vgg19` `preprocess_input` | `"caffe"` |

You do **not** need to set:

- **Input size:** read from the model (e.g. 224×224 or 256×256). Only set `IMAGE_SIZE` if your model accepts any size.
- **Softmax:** if the last layer outputs raw logits, softmax is applied automatically.
- **Image format:** photos are converted to RGB and rotated upright (EXIF) automatically.

### Step 5: Check the model before starting the server

Use a few images whose correct label you **know** (e.g. from your validation set):

```powershell
python check_model.py C:\data\val\tomato__late_blight\img1.jpg C:\data\val\potato__healthy\img7.jpg
```

Example output:

```
preprocessing = 'rescale_0_1', input size = (224, 224)

img1.jpg
     97.3%  tomato__late_blight
      1.2%  tomato__early_blight
      0.5%  potato__late_blight
```

- **Correct and confident** → done.
- **Wrong, or always the same class, or always low confidence** → wrong `PREPROCESSING` or wrong
  `labels.txt` order. Try another value without editing the file:
  `$env:PREPROCESSING="rescale_-1_1"; python check_model.py ...`

### Step 6: Start the server in real mode

```powershell
.\.venv-real\Scripts\Activate.ps1
$env:MODEL_MODE="real"
uvicorn main:app --host 0.0.0.0 --port 8000
```

(cmd: `set MODEL_MODE=real`; macOS/Linux: `MODEL_MODE=real uvicorn main:app --host 0.0.0.0 --port 8000`.)

On startup you should see:

```
[predictor] loading model.keras ...
[predictor] ready: 19 classes, input (224, 224), preprocessing='rescale_0_1'
```

Then http://localhost:8000/health must return:

```json
{"status": "ok", "model_loaded": true, "mode": "real"}
```

That's it: the Flutter app now shows real predictions with no changes.

---

## Troubleshooting

| Message | Fix |
|---|---|
| `No matching distribution found for tensorflow` | You are on Python 3.13/3.14. Use the 3.11/3.12 venv (step 1). |
| `MODEL_MODE=real needs TensorFlow` | You started uvicorn from the mock `.venv`. Activate `.venv-real`. |
| `Model file not found` | Put `model.keras` in the `api/` folder (next to `main.py`). |
| `Model has N outputs but labels.txt has M labels` | `labels.txt` has missing or extra lines. |
| `Label '...' must look like crop__disease` | Use two underscores between crop and disease. |
| Error while loading the `.keras` file | Install the same TensorFlow version used for training. |
| Predictions look random | Wrong `PREPROCESSING` or wrong label order (step 3/5). |
| `/health` says `"mode": "mock"` | `MODEL_MODE` was not set in **the same terminal** before `uvicorn`. |

---

## Files

| File | Purpose |
|---|---|
| `main.py` | HTTP routes only. No need to edit. |
| `predictor.py` | Loads the model and predicts. Only the **SETTINGS** block may need editing. |
| `labels.txt` | One label per line, in model output order. |
| `check_model.py` | Tests the model on images from the command line. |
| `requirements.txt` | Mock mode packages. |
| `requirements-real.txt` | Real mode packages (adds TensorFlow). |

Environment variables (all optional): `MODEL_MODE` (`mock`/`real`), `PREPROCESSING`, `MODEL_PATH`, `LABELS_PATH`.

## API contract (the app depends on this; do not change it)

```
GET  /health  -> {"status": "ok", "model_loaded": true|false, "mode": "mock"|"real"}

POST /predict   multipart/form-data, field "image" (jpg/png, max 10 MB)
  200 -> {"label": "tomato__late_blight", "crop": "tomato", "disease": "late_blight",
          "is_healthy": false, "confidence": 0.92,
          "top3": [{"label": "tomato__late_blight", "confidence": 0.92}, ...]}
  400 -> {"error": "..."}   missing / invalid / unsupported image
  500 -> {"error": "..."}   unexpected model failure
```

## Connecting the Flutter app

- **Android emulator:** works as is (the app uses `http://10.0.2.2:8000`).
- **Real phone:** phone and PC on the same Wi-Fi; find the PC's IP with `ipconfig` (IPv4 Address), then:
  ```powershell
  cd ..\app
  flutter run --dart-define=API_BASE_URL=http://192.168.1.15:8000
  ```
  If the phone can't connect, allow Python through Windows Firewall (private networks).
