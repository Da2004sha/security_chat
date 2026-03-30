import asyncio
import os
from time import time

from fastapi import (
    FastAPI,
    Depends,
    HTTPException,
    UploadFile,
    File,
    WebSocket,
    Query,
    Form,
)
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import select
from fastapi.responses import FileResponse
from jose import jwt

from .db import engine, Base, get_db
from .models import User, Device, Chat, ChatMember, Message, Attachment, ChatKey
from .schemas import *
from .auth import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)
from .config import UPLOAD_DIR, MAX_UPLOAD_MB, JWT_SECRET, JWT_ALG
from .realtime import manager

app = FastAPI(title="Secure Corporate Chat Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _ensure_chat_member(db: Session, chat_id: int, user_id: int):
    member = db.scalar(
        select(ChatMember).where(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id == user_id,
        )
    )
    if not member:
        raise HTTPException(403, "Not a member")
    return member


@app.on_event("startup")
def on_startup():
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    Base.metadata.create_all(bind=engine)


@app.post("/auth/register", response_model=TokenOut)
def register(data: RegisterIn, db: Session = Depends(get_db)):
    existing = db.scalar(select(User).where(User.username == data.username))
    if existing:
        raise HTTPException(status_code=400, detail="Username already exists")

    user = User(
        username=data.username,
        password_hash=hash_password(data.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id)
    return TokenOut(access_token=token, user_id=user.id)


@app.post("/auth/login", response_model=TokenOut)
def login(data: RegisterIn, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.username == data.username))
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_access_token(user.id)
    return TokenOut(access_token=token, user_id=user.id)


@app.post("/devices", response_model=DeviceOut)
def add_device(
    data: AddDeviceIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    existing = db.scalar(
        select(Device).where(
            Device.user_id == user.id,
            Device.pubkey_b64 == data.pubkey_b64,
            Device.is_active == True,
        )
    )
    if existing:
        if getattr(existing, "sign_pubkey_b64", "") != data.sign_pubkey_b64:
            existing.sign_pubkey_b64 = data.sign_pubkey_b64
            db.commit()
            db.refresh(existing)
        return DeviceOut(
            id=existing.id,
            device_name=existing.device_name,
            pubkey_b64=existing.pubkey_b64,
            sign_pubkey_b64=existing.sign_pubkey_b64 or "",
            is_active=existing.is_active,
        )

    d = Device(
        user_id=user.id,
        device_name=data.device_name,
        pubkey_b64=data.pubkey_b64,
        sign_pubkey_b64=data.sign_pubkey_b64,
        is_active=True,
    )
    db.add(d)
    db.commit()
    db.refresh(d)

    return DeviceOut(
        id=d.id,
        device_name=d.device_name,
        pubkey_b64=d.pubkey_b64,
        sign_pubkey_b64=d.sign_pubkey_b64 or "",
        is_active=d.is_active,
    )


@app.get("/users/{username}", response_model=UserOut)
def get_user_by_username(
    username: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    u = db.scalar(select(User).where(User.username == username))
    if not u:
        raise HTTPException(404, "Not found")
    return UserOut(id=u.id, username=u.username)


@app.get("/users/{user_id}/devices", response_model=list[DeviceOut])
def list_user_devices(
    user_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    devices = db.scalars(
        select(Device).where(
            Device.user_id == user_id,
            Device.is_active == True,
        )
    ).all()

    return [
        DeviceOut(
            id=d.id,
            device_name=d.device_name,
            pubkey_b64=d.pubkey_b64,
            sign_pubkey_b64=d.sign_pubkey_b64 or "",
            is_active=d.is_active,
        )
        for d in devices
    ]


@app.post("/chats", response_model=ChatOut)
def create_chat(
    data: ChatCreateIn,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    usernames = set(data.member_usernames)
    usernames.add(me.username)

    users = db.scalars(select(User).where(User.username.in_(list(usernames)))).all()
    if len(users) != len(usernames):
        raise HTTPException(400, "One or more usernames not found")

    chat = Chat(is_group=data.is_group, title=data.title)
    db.add(chat)
    db.commit()
    db.refresh(chat)

    for u in users:
        db.add(ChatMember(chat_id=chat.id, user_id=u.id))
    db.commit()

    return ChatOut(id=chat.id, is_group=chat.is_group, title=chat.title)


@app.get("/chats", response_model=list[ChatOut])
def list_my_chats(
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    chat_ids = db.scalars(
        select(ChatMember.chat_id).where(ChatMember.user_id == me.id)
    ).all()

    if not chat_ids:
        return []

    chats = db.scalars(
        select(Chat).where(Chat.id.in_(chat_ids)).order_by(Chat.created_at.desc())
    ).all()

    return [ChatOut(id=c.id, is_group=c.is_group, title=c.title) for c in chats]


@app.delete("/chats/{chat_id}")
def delete_chat(
    chat_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, chat_id, me.id)

    chat = db.get(Chat, chat_id)
    if not chat:
        raise HTTPException(404, "Chat not found")

    attachments = db.scalars(select(Attachment).where(Attachment.chat_id == chat_id)).all()
    for att in attachments:
        try:
            if os.path.exists(att.path):
                os.remove(att.path)
        except OSError:
            pass
        db.delete(att)

    messages = db.scalars(select(Message).where(Message.chat_id == chat_id)).all()
    for msg in messages:
        db.delete(msg)

    chat_keys = db.scalars(select(ChatKey).where(ChatKey.chat_id == chat_id)).all()
    for key in chat_keys:
        db.delete(key)

    members = db.scalars(select(ChatMember).where(ChatMember.chat_id == chat_id)).all()
    for member in members:
        db.delete(member)

    db.delete(chat)
    db.commit()

    return {"status": "deleted", "chat_id": chat_id}


@app.get("/chats/{chat_id}/members", response_model=list[UserOut])
def list_chat_members(
    chat_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, chat_id, me.id)

    user_ids = db.scalars(
        select(ChatMember.user_id).where(ChatMember.chat_id == chat_id)
    ).all()

    users = db.scalars(select(User).where(User.id.in_(user_ids))).all()
    return [UserOut(id=u.id, username=u.username) for u in users]


@app.post("/chat_keys")
def upsert_chat_key(
    data: ChatKeyIn,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, data.chat_id, me.id)

    sender_device = db.get(Device, data.wrapped_by_device_id)
    if not sender_device or sender_device.user_id != me.id:
        raise HTTPException(400, "Invalid wrapped_by_device_id")

    target_device = db.get(Device, data.device_id)
    if not target_device or not target_device.is_active:
        raise HTTPException(400, "Invalid target device")

    existing = db.scalar(
        select(ChatKey).where(
            ChatKey.chat_id == data.chat_id,
            ChatKey.device_id == data.device_id,
        )
    )

    if existing:
        existing.wrapped_by_device_id = data.wrapped_by_device_id
        existing.wrapped_key_json = data.wrapped_key_json
        db.commit()
        return {"status": "updated"}

    ck = ChatKey(
        chat_id=data.chat_id,
        device_id=data.device_id,
        wrapped_by_device_id=data.wrapped_by_device_id,
        wrapped_key_json=data.wrapped_key_json,
    )
    db.add(ck)
    db.commit()
    return {"status": "created"}


@app.get("/chat_keys/mine", response_model=list[ChatKeyOut])
def get_my_chat_keys(
    device_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    my_device = db.get(Device, device_id)
    if not my_device or my_device.user_id != me.id:
        raise HTTPException(400, "Invalid device")

    keys = db.scalars(select(ChatKey).where(ChatKey.device_id == device_id)).all()

    out: list[ChatKeyOut] = []
    for k in keys:
        wrapped_by = db.get(Device, k.wrapped_by_device_id)
        if wrapped_by is None:
            continue
        out.append(
            ChatKeyOut(
                chat_id=k.chat_id,
                device_id=k.device_id,
                wrapped_by_device_id=k.wrapped_by_device_id,
                wrapped_key_json=k.wrapped_key_json,
                wrapped_by_pubkey_b64=wrapped_by.pubkey_b64,
            )
        )
    return out


@app.get("/chat_keys/by_chat/{chat_id}", response_model=list[ChatKeyDeviceOut])
def get_chat_key_devices(
    chat_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, chat_id, me.id)

    rows = db.scalars(select(ChatKey).where(ChatKey.chat_id == chat_id)).all()
    return [ChatKeyDeviceOut(device_id=r.device_id) for r in rows]


@app.post("/messages", response_model=MessageOut)
def send_message(
    data: MessageIn,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, data.chat_id, me.id)

    dev = db.get(Device, data.sender_device_id)
    if not dev or dev.user_id != me.id:
        raise HTTPException(400, "Invalid device")

    msg = Message(
        chat_id=data.chat_id,
        sender_user_id=me.id,
        sender_device_id=data.sender_device_id,
        payload_json=data.payload_json,
        signature_b64=data.signature_b64,
        sig_alg=data.sig_alg,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)

    member_ids = db.scalars(
        select(ChatMember.user_id).where(ChatMember.chat_id == data.chat_id)
    ).all()

    out = MessageOut(
        id=msg.id,
        chat_id=msg.chat_id,
        sender_user_id=msg.sender_user_id,
        sender_device_id=msg.sender_device_id,
        payload_json=msg.payload_json,
        signature_b64=msg.signature_b64,
        sig_alg=msg.sig_alg,
        created_at=msg.created_at.isoformat(),
    )

    for uid in member_ids:
        try:
            asyncio.create_task(
                manager.send_to_user(uid, {"type": "message", "data": out.model_dump()})
            )
        except RuntimeError:
            pass

    return out


@app.get("/chats/{chat_id}/messages", response_model=list[MessageOut])
def list_messages(
    chat_id: int,
    limit: int = 50,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, chat_id, me.id)

    msgs = db.scalars(
        select(Message)
        .where(Message.chat_id == chat_id)
        .order_by(Message.id.desc())
        .limit(limit)
    ).all()

    msgs = list(reversed(msgs))

    return [
        MessageOut(
            id=m.id,
            chat_id=m.chat_id,
            sender_user_id=m.sender_user_id,
            sender_device_id=m.sender_device_id,
            payload_json=m.payload_json,
            signature_b64=m.signature_b64,
            sig_alg=m.sig_alg,
            created_at=m.created_at.isoformat(),
        )
        for m in msgs
    ]


@app.post("/attachments", response_model=UploadOut)
async def upload_attachment(
    chat_id: int = Form(...),
    file: UploadFile = File(...),
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _ensure_chat_member(db, chat_id, me.id)

    max_bytes = MAX_UPLOAD_MB * 1024 * 1024
    data = await file.read()
    if len(data) > max_bytes:
        raise HTTPException(413, f"Max upload {MAX_UPLOAD_MB}MB")

    safe_name = os.path.basename(file.filename or "blob.e2ee")
    disk_name = f"chat{chat_id}_{me.id}_{int(time())}_{safe_name}"
    path = os.path.join(UPLOAD_DIR, disk_name)

    with open(path, "wb") as f:
        f.write(data)

    att = Attachment(
        owner_user_id=me.id,
        chat_id=chat_id,
        filename=safe_name,
        content_type=file.content_type or "application/octet-stream",
        size_bytes=len(data),
        path=path,
    )
    db.add(att)
    db.commit()
    db.refresh(att)

    return UploadOut(
        attachment_id=att.id,
        filename=att.filename,
        content_type=att.content_type,
        size_bytes=att.size_bytes,
    )


@app.get("/attachments/{attachment_id}")
def download_attachment(
    attachment_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    att = db.get(Attachment, attachment_id)
    if not att:
        raise HTTPException(404, "Not found")

    _ensure_chat_member(db, att.chat_id, me.id)
    if not os.path.exists(att.path):
        raise HTTPException(404, "Attachment file not found")

    return FileResponse(att.path, media_type=att.content_type, filename=att.filename)


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket, token: str = Query(...)):
    try:
        data = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALG])
        user_id = int(data["sub"])
    except Exception:
        await ws.close(code=1008)
        return

    await manager.connect(user_id, ws)
    try:
        while True:
            await ws.receive_text()
    except Exception:
        pass
