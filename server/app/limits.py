import asyncio
import math
import time
from collections import defaultdict, deque


class SlidingWindowRateLimiter:
    def __init__(self, *, max_requests: int, window_seconds: int) -> None:
        self._max_requests = max_requests
        self._window_seconds = window_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def allow(self, key: str) -> tuple[bool, int]:
        now = time.monotonic()
        cutoff = now - self._window_seconds
        async with self._lock:
            events = self._events[key]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= self._max_requests:
                retry_after = max(1, math.ceil(events[0] + self._window_seconds - now))
                return False, retry_after
            events.append(now)
            return True, 0


class ConcurrencyLimiter:
    def __init__(self, max_concurrent: int) -> None:
        self._max_concurrent = max_concurrent
        self._in_flight = 0
        self._lock = asyncio.Lock()

    async def try_acquire(self) -> bool:
        async with self._lock:
            if self._in_flight >= self._max_concurrent:
                return False
            self._in_flight += 1
            return True

    async def release(self) -> None:
        async with self._lock:
            self._in_flight = max(0, self._in_flight - 1)
