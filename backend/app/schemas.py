from pydantic import BaseModel, Field
from typing import Optional, List


class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=6, max_length=128)


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int


class AddDeviceIn(BaseModel):
    device_name: str
    pubkey_b64: str


class DeviceOut(BaseModel):
    id: int
    device_name: str
    pubkey_b64: str
    is_active: bool


class UserOut(BaseModel):
    id: int
    username: str


class ChatCreateIn(BaseModel):
    member_usernames: List[str] = Field(min_length=1)
    is_group: bool = False
    title: Optional[str] = None


class ChatOut(BaseModel):
    id: int
    is_group: bool
    title: Optional[str]


class MessageIn(BaseModel):
    chat_id: int
    payload_json: str
    sender_device_id: int


class MessageOut(BaseModel):
    id: int
    chat_id: int
    sender_user_id: int
    sender_device_id: int
    payload_json: str
    created_at: str


class UploadOut(BaseModel):
    attachment_id: int
    filename: str
    content_type: str
    size_bytes: int


class ChatKeyIn(BaseModel):
    chat_id: int
    device_id: int
    wrapped_by_device_id: int
    wrapped_key_json: str


class ChatKeyOut(BaseModel):
    chat_id: int
    device_id: int
    wrapped_by_device_id: int
    wrapped_key_json: str
    wrapped_by_pubkey_b64: str


class ChatKeyDeviceOut(BaseModel):
    device_id: int