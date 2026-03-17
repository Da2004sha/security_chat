from datetime import datetime, timedelta

from jose import jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from .config import JWT_SECRET, JWT_ALG, ACCESS_TOKEN_MINUTES
from .db import get_db
from .models import User

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def hash_password(pw: str) -> str:
    """
    bcrypt limitation: it only uses the first 72 BYTES of the password.
    We enforce this explicitly to avoid runtime crashes.
    """
    pw_bytes = pw.encode("utf-8")
    if len(pw_bytes) > 72:
        pw_bytes = pw_bytes[:72]
    # Passlib accepts str; we convert bytes back safely
    pw_safe = pw_bytes.decode("utf-8", errors="ignore")
    return pwd_context.hash(pw_safe)


def verify_password(pw: str, hashed: str) -> bool:
    pw_bytes = pw.encode("utf-8")
    if len(pw_bytes) > 72:
        pw_bytes = pw_bytes[:72]
    pw_safe = pw_bytes.decode("utf-8", errors="ignore")
    return pwd_context.verify(pw_safe, hashed)


def create_access_token(user_id: int) -> str:
    exp = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_MINUTES)
    payload = {"sub": str(user_id), "exp": exp}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    try:
        data = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALG])
        user_id = int(data["sub"])
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )

    user = db.get(User, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )
    return user