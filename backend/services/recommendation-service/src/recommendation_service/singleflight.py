from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import Generic, TypeVar

T = TypeVar("T")


class SingleFlight(Generic[T]):
    """Coalesce concurrent identical work inside one process: the first caller computes, the rest await its result.

    Under load many users submit the same profile shape (e.g. app defaults); this keeps the expensive LLM call to
    one per key at a time. Across replicas the shared Redis cache does the same job once the first result lands.
    """

    def __init__(self) -> None:
        self._inflight: dict[str, asyncio.Future] = {}

    @property
    def in_flight(self) -> int:
        return len(self._inflight)

    async def do(self, key: str, fn: Callable[[], Awaitable[T]]) -> tuple[T, bool]:
        """Returns (result, shared) where shared=True means another caller's computation was reused."""
        fut = self._inflight.get(key)
        if fut is not None:
            return await asyncio.shield(fut), True
        fut = asyncio.get_running_loop().create_future()
        fut.add_done_callback(lambda f: f.cancelled() or f.exception())  # never "exception was never retrieved"
        self._inflight[key] = fut
        try:
            result = await fn()
        except BaseException as e:
            if not fut.done():
                fut.set_exception(e)
            raise
        else:
            fut.set_result(result)
            return result, False
        finally:
            self._inflight.pop(key, None)
