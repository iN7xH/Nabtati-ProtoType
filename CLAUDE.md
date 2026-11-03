# Prototype: AI Plant Disease Detection (Flutter + Python API)

## Context
- CS graduation project, University of Petra, Jordan. LIGHT PROTOTYPE requested by our supervisor.
- I (Yousef) build the Flutter app and the Python API. I know Java, Python and JavaScript but I am NEW
  to Flutter/Dart: explain Flutter concepts briefly, keep code simple and commented, and tell me how to
  run and test each step.
- My teammate trains the model separately and will plug it into the API. Until then the API returns a
  MOCK prediction, so the app can be built and tested end to end.

## Prototype goal (ONLY this)
User picks a leaf image in the app -> app sends it to the API -> app shows crop, disease (or Healthy),
and confidence. NO treatment pages, NO chatbot, NO history, NO database, NO login.
Do not add anything outside this scope without asking me.

## Classes (19 labels, format crop__disease)
- tomato: healthy, early_blight, late_blight, bacterial_spot, septoria_leaf_spot, leaf_mold,
  yellow_leaf_curl_virus, mosaic_virus, spider_mites, target_spot
- potato: healthy, early_blight, late_blight
- pepper: healthy, bacterial_spot
- cucumber: healthy, downy_mildew, gummy_stem_blight, anthracnose

## Project structure
/app      Flutter app (Android first)
/api      FastAPI (Python)
  main.py          routes only
  predictor.py     the ONLY file my teammate edits to load the real model
  labels.txt       19 labels, one per line, same order as the model output
  requirements.txt
  README.md        how to run, and exactly how to plug in the real model

## API contract (must not change once the app uses it)
GET  /health  -> {"status": "ok", "model_loaded": true|false, "mode": "mock"|"real"}
POST /predict  multipart/form-data, field name "image" (jpg/png)
  200 -> {
    "label": "tomato__late_blight",
    "crop": "tomato",
    "disease": "late_blight",
    "is_healthy": false,
    "confidence": 0.92,
    "top3": [{"label": "...", "confidence": 0.92}, ...]
  }
  400 -> {"error": "..."} for missing or invalid image

## predictor.py design
- A `Predictor` class with `load()` and `predict(image_bytes) -> list of (label, confidence)`.
- MOCK mode by default: returns a random label with a plausible confidence, so everything works now.
- REAL mode: loads a Keras model file (model.keras) + labels.txt, resizes to 224x224, applies the SAME
  preprocessing used in training, returns softmax scores. Mark clearly with TODO comments where the
  teammate must confirm input size and preprocessing.
- Switch with an env variable, e.g. MODEL_MODE=mock|real.

## Flutter app (one screen is enough)
- "Pick image" button (image_picker, gallery; camera optional) -> show selected image.
- "Diagnose" button -> POST to /predict with the `http` package -> show loading -> show result card:
  crop, disease (or Healthy), confidence.
- If confidence < 0.70 show "Not sure, try a clearer photo of one leaf".
- Handle errors: server unreachable, timeout, invalid response.
- API base URL in one config constant. Android emulator uses http://10.0.2.2:8000;
  a real phone uses the PC's local IP on the same Wi-Fi (run uvicorn with --host 0.0.0.0).
- Simple, clean UI. Arabic or English labels are fine.

## Order of work
1. API with mock predictor + test /predict with curl or Swagger (/docs)
2. Flutter project setup
3. Pick and display image
4. Call the API and show the result
5. Error handling and loading state
6. README for the teammate on plugging in the real model