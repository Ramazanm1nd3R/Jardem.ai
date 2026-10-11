"""Event fan-out to WebSocket clients: in-process, or through Redis pub/sub."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging

log = logging.getLogger("jardem.bus")
CHANNEL = "jardem:events"


class LocalBus:
    """Delivers events to subscribers within this process."""

    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue[str]] = set()

    async def start(self) -> None:
        return None

    async def stop(self) -> None:
        return None

    def subscribe(self) -> asyncio.Queue[str]:
        queue: asyncio.Queue[str] = asyncio.Queue(maxsize=256)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[str]) -> None:
        self._subscribers.discard(queue)

    def _deliver(self, raw: str) -> None:
        for queue in list(self._subscribers):
            if queue.full():
                # A slow client loses its oldest event rather than stalling everyone.
                with contextlib.suppress(asyncio.QueueEmpty):
                    queue.get_nowait()
            queue.put_nowait(raw)

    async def publish(self, event: dict) -> None:
        self._deliver(json.dumps(event, ensure_ascii=False))


class RedisBus(LocalBus):
    """Publishes through Redis so every backend replica's clients see every event."""

    def __init__(self, url: str) -> None:
        super().__init__()
        import redis.asyncio as redis

        self._redis = redis.from_url(url, decode_responses=True)
        self._task: asyncio.Task | None = None

    @property
    def redis(self):
        return self._redis

    async def start(self) -> None:
        await self._redis.ping()
        self._task = asyncio.create_task(self._listen())

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        await self._redis.aclose()

    async def _listen(self) -> None:
        while True:
            try:
                pubsub = self._redis.pubsub()
                await pubsub.subscribe(CHANNEL)
                async for message in pubsub.listen():
                    if message["type"] == "message":
                        self._deliver(message["data"])
            except asyncio.CancelledError:
                raise
            except Exception:
                log.exception("redis subscription lost; retrying")
                await asyncio.sleep(1.0)

    async def publish(self, event: dict) -> None:
        await self._redis.publish(CHANNEL, json.dumps(event, ensure_ascii=False))
