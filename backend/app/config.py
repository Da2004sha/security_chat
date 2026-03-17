import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg://chat:chat@db:5432/chat")
JWT_SECRET = os.getenv("JWT_SECRET", "CHANGE_ME_IN_PROD")
JWT_ALG = "HS256"
ACCESS_TOKEN_MINUTES = int(os.getenv("ACCESS_TOKEN_MINUTES", "60"))

UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/data/uploads")
MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", "50"))
