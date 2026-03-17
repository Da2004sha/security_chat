import os
import time

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from sqlalchemy.exc import OperationalError


# Берём DATABASE_URL из окружения (Docker),
# если нет — используем дефолт (на будущее)
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://secure:secure@db:5432/secure_chat"
)


def create_engine_with_retry(url: str, retries: int = 10, delay: int = 2):
    """
    Ждём, пока PostgreSQL станет доступен.
    Это убирает race condition при старте Docker Compose.
    """
    for attempt in range(1, retries + 1):
        try:
            engine = create_engine(url, pool_pre_ping=True)
            # пробуем реально подключиться
            with engine.connect():
                return engine
        except OperationalError:
            print(
                f"[DB] Waiting for database... "
                f"attempt {attempt}/{retries}"
            )
            time.sleep(delay)

    raise RuntimeError("Database is not available after multiple retries")


engine = create_engine_with_retry(DATABASE_URL)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()