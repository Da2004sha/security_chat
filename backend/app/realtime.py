import asyncio
from typing import Dict, Set
from fastapi import WebSocket

# Simple in-memory connection manager: user_id -> set[WebSocket]
# For production you'd use Redis/pubsub, etc.
class ConnectionManager:
    def __init__(self):
        self._lock = asyncio.Lock()
        self._conns: Dict[int, Set[WebSocket]] = {}

    async def connect(self, user_id: int, ws: WebSocket):
        await ws.accept()
        async with self._lock:
            self._conns.setdefault(user_id, set()).add(ws)

    async def disconnect(self, user_id: int, ws: WebSocket):
        async with self._lock:
            if user_id in self._conns and ws in self._conns[user_id]:
                self._conns[user_id].remove(ws)
                if not self._conns[user_id]:
                    del self._conns[user_id]

    async def send_to_user(self, user_id: int, message: dict):
        async with self._lock:
            conns = list(self._conns.get(user_id, set()))
        for ws in conns:
            try:
                await ws.send_json(message)
            except Exception:
                # Ignore errors; disconnect will happen on next recv
                pass

manager = ConnectionManager()
