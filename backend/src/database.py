from collections.abc import AsyncGenerator
import os
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import AsyncSession , create_async_engine , async_sessionmaker
from sqlalchemy.orm import DeclarativeBase , relationship

load_dotenv()

class Base(DeclarativeBase):
    pass

POSTGRES_USERNAME = os.getenv("POSTGRES_USERNAME" , "")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD" , "")
POSTGRES_DB = os.getenv("POSTGRES_DB" , "")
POSTGRES_HOST = os.getenv("POSTGRES_HOST" , "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT" , "5432")

DATABASE_URL = f"postgresql+psycopg://{POSTGRES_USERNAME}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
engine = create_async_engine(DATABASE_URL)
async_session_maker = async_sessionmaker(engine , expire_on_commit=False)

async def create_db_and_tables():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_async_session() -> AsyncGenerator[AsyncSession,None]:
    async with async_session_maker() as session:
        yield session
