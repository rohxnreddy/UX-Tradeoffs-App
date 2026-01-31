from fastapi import FastAPI, HTTPException, File, UploadFile, Form, Depends
from src.database import create_db_and_tables, get_async_session
from sqlalchemy.ext.asyncio import AsyncSession
from contextlib import asynccontextmanager
from sqlalchemy import select
from pathlib import Path
from tempfile import NamedTemporaryFile

from src.vmaf.vmaf import compute_vmaf

@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_db_and_tables()
    yield

app = FastAPI(lifespan=lifespan)


@app.get("/")
def init():
    return {"message": "Server is Up!"}


@app.post("/vmaf/score")
async def calculate_vmaf(
    distorted_video: UploadFile = File(...),
):
    contents = await distorted_video.read()
    if not contents:
        raise HTTPException(400, "Empty file uploaded")

    suffix = Path(distorted_video.filename or "").suffix or ".mp4"

    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents)
        original_path = Path(tmp.name)

    try:
        score = compute_vmaf(original_path)

        return {
            "vmaf_score": score,
        }

    finally:
        original_path.unlink(missing_ok=True)