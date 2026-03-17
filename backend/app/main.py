import os
import json
from fastapi import (
    FastAPI,
    Depends,
    HTTPException,
    UploadFile,
    File,
    WebSocket,
    Query,
    Request,
)
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import select

from .db import engine, Base, get_db
from .models import User, Device, Chat, ChatMember, Message, Attachment
from .schemas import *
from .auth import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)
from .config import UPLOAD_DIR, MAX_UPLOAD_MB, JWT_SECRET, JWT_ALG
from jose import jwt
from .realtime import manager

app = FastAPI(title="Secure Corporate Chat Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # dev only
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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
        return DeviceOut(
            id=existing.id,
            device_name=existing.device_name,
            pubkey_b64=existing.pubkey_b64,
            is_active=existing.is_active,
        )

    d = Device(
        user_id=user.id,
        device_name=data.device_name,
        pubkey_b64=data.pubkey_b64,
        is_active=True,
    )
    db.add(d)
    db.commit()
    db.refresh(d)

    return DeviceOut(
        id=d.id,
        device_name=d.device_name,
        pubkey_b64=d.pubkey_b64,
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


@app.get("/chats/{chat_id}/members", response_model=list[UserOut])
def list_chat_members(
    chat_id: int,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    is_member = db.scalar(
        select(ChatMember).where(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id == me.id,
        )
    )
    if not is_member:
        raise HTTPException(403, "Not a member")

    user_ids = db.scalars(
        select(ChatMember.user_id).where(ChatMember.chat_id == chat_id)
    ).all()

    users = db.scalars(select(User).where(User.id.in_(user_ids))).all()
    return [UserOut(id=u.id, username=u.username) for u in users]


def _normalize_payload_json_for_storage(
    raw_body: dict,
    me: User,
    db: Session,
) -> tuple[int, int, str]:
    chat_id = raw_body.get("chat_id")
    sender_device_id = raw_body.get("sender_device_id")

    if chat_id is None or sender_device_id is None:
        raise HTTPException(422, "chat_id and sender_device_id are required")

    dev = db.get(Device, int(sender_device_id))
    if not dev or dev.user_id != me.id:
        raise HTTPException(400, "Invalid device")

    if "payload_json" in raw_body and raw_body.get("payload_json") is not None:
        payload_json = raw_body["payload_json"]
        if not isinstance(payload_json, str) or not payload_json.strip():
            raise HTTPException(422, "payload_json must be a non-empty string")
        return int(chat_id), int(sender_device_id), payload_json

    payloads = raw_body.get("payloads")
    if not isinstance(payloads, list) or len(payloads) == 0:
        raise HTTPException(422, "Either payload_json or non-empty payloads is required")

    payload_map: dict[str, str] = {}

    for item in payloads:
        if not isinstance(item, dict):
            raise HTTPException(422, "Each payload must be an object")

        recipient_device_id = item.get("recipient_device_id")
        payload_json = item.get("payload_json")

        if recipient_device_id is None or payload_json is None:
            raise HTTPException(
                422,
                "recipient_device_id and payload_json are required in each payload",
            )

        target_device = db.get(Device, int(recipient_device_id))
        if not target_device or not target_device.is_active:
            raise HTTPException(400, f"Invalid recipient device: {recipient_device_id}")

        if not isinstance(payload_json, str) or not payload_json.strip():
            raise HTTPException(
                422,
                f"payload_json for recipient_device_id={recipient_device_id} must be a non-empty string",
            )

        payload_map[str(int(recipient_device_id))] = payload_json

    wrapped = {
        "multi_device": True,
        "payloads": payload_map,
    }

    return int(chat_id), int(sender_device_id), json.dumps(wrapped, ensure_ascii=False)


@app.post("/messages", response_model=MessageOut)
async def send_message(
    request: Request,
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    raw_body = await request.json()

    chat_id, sender_device_id, payload_json_to_store = _normalize_payload_json_for_storage(
        raw_body, me, db
    )

    is_member = db.scalar(
        select(ChatMember).where(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id == me.id,
        )
    )
    if not is_member:
        raise HTTPException(403, "Not a member")

    msg = Message(
        chat_id=chat_id,
        sender_user_id=me.id,
        sender_device_id=sender_device_id,
        payload_json=payload_json_to_store,
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)

    member_ids = db.scalars(
        select(ChatMember.user_id).where(ChatMember.chat_id == chat_id)
    ).all()

    out = MessageOut(
        id=msg.id,
        chat_id=msg.chat_id,
        sender_user_id=msg.sender_user_id,
        sender_device_id=msg.sender_device_id,
        payload_json=msg.payload_json,
        created_at=msg.created_at.isoformat(),
    )

    for uid in member_ids:
        try:
            import asyncio
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
    is_member = db.scalar(
        select(ChatMember).where(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id == me.id,
        )
    )
    if not is_member:
        raise HTTPException(403, "Not a member")

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
            created_at=m.created_at.isoformat(),
        )
        for m in msgs
    ]


@app.post("/attachments", response_model=UploadOut)
async def upload_attachment(
    file: UploadFile = File(...),
    me: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    max_bytes = MAX_UPLOAD_MB * 1024 * 1024
    data = await file.read()

    if len(data) > max_bytes:
        raise HTTPException(413, f"Max upload {MAX_UPLOAD_MB}MB")

    safe_name = os.path.basename(file.filename or "file.bin")
    disk_name = f"{me.id}_{int(__import__('time').time())}_{safe_name}"
    path = os.path.join(UPLOAD_DIR, disk_name)

    with open(path, "wb") as f:
        f.write(data)

    att = Attachment(
        owner_user_id=me.id,
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

    from fastapi.responses import FileResponse
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
    finally:
        await manager.disconnect(user_id, ws)