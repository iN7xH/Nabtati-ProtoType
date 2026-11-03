"""
main.py - HTTP routes only. All model logic lives in predictor.py.

Run:  uvicorn main:app --reload --host 0.0.0.0 --port 8000
Docs: http://localhost:8000/docs
"""

import io
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Request, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from PIL import Image, UnidentifiedImageError

from predictor import Predictor, split_label

ALLOWED_FORMATS = {"JPEG", "PNG"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB

predictor = Predictor()


@asynccontextmanager
async def lifespan(app: FastAPI):
    predictor.load()  # load the model once at startup (no-op in mock mode)
    print(f"[api] mode={predictor.mode} model_loaded={predictor.model_loaded}")
    yield


app = FastAPI(title="Plant Disease Detection API", version="0.1.0", lifespan=lifespan)


def error(message: str, status: int = 400) -> JSONResponse:
    """All errors use the contract shape: {"error": "..."}"""
    return JSONResponse(status_code=status, content={"error": message})


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    # FastAPI would normally return 422 with its own format; the contract says 400 {"error"}.
    return error("Invalid request. Send multipart/form-data with field 'image'.")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": predictor.model_loaded,
        "mode": predictor.mode,
    }


@app.post("/predict")
async def predict(image: UploadFile | None = File(None)):
    # 1. Field present?
    if image is None:
        return error("Missing file field 'image'.")

    data = await image.read()
    if not data:
        return error("Uploaded image is empty.")
    if len(data) > MAX_UPLOAD_BYTES:
        return error("Image is too large (max 10 MB).")

    # 2. Is it really a JPG/PNG? (check the content, not just the file name)
    try:
        with Image.open(io.BytesIO(data)) as img:
            fmt = img.format
            img.verify()
    except (UnidentifiedImageError, OSError):
        return error("File is not a valid image.")
    if fmt not in ALLOWED_FORMATS:
        return error(f"Unsupported image format '{fmt}'. Use JPG or PNG.")

    # 3. Run the predictor in a worker thread (model inference is slow, CPU-bound code;
    #    this keeps the server responsive to other requests meanwhile).
    try:
        results = await run_in_threadpool(predictor.predict, data)
    except Exception as exc:  # unexpected model failure
        print(f"[api] prediction failed: {exc!r}")
        return error(f"Prediction failed: {exc}", status=500)

    # 4. Build the response in the agreed contract format
    label, confidence = results[0]
    crop, disease = split_label(label)
    return {
        "label": label,
        "crop": crop,
        "disease": disease,
        "is_healthy": disease == "healthy",
        "confidence": round(confidence, 4),
        "top3": [{"label": l, "confidence": round(c, 4)} for l, c in results[:3]],
    }
