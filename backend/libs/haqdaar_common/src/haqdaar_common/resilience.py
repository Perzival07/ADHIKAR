"""A small circuit breaker for inter-service HTTP clients (infrastructure only)."""
from __future__ import annotations

import time
from collections.abc import Callable


class CircuitOpen(Exception):
    """Raised instead of calling a dependency that has been failing; fail fast, retry later."""


class CircuitBreaker:
    """closed -> (N consecutive failures) -> open -> (after reset_timeout) -> half-open -> success: closed / failure: open.

    Only dependency failures count (connection errors, timeouts, 5xx). Client errors (4xx) and backpressure (429) do not.
    """

    def __init__(self, name: str, failure_threshold: int = 5, reset_timeout: float = 30.0,
                 clock: Callable[[], float] = time.monotonic, on_open: Callable[[str], None] | None = None):
        self.name, self.threshold, self.reset_timeout, self._clock, self._on_open = name, failure_threshold, reset_timeout, clock, on_open
        self.failures = 0
        self.opened_at: float | None = None
        self._trial_in_flight = False

    @property
    def state(self) -> str:
        if self.opened_at is None:
            return "closed"
        if self._clock() - self.opened_at >= self.reset_timeout:
            return "half_open"
        return "open"

    def before_call(self) -> None:
        s = self.state
        if s == "open":
            raise CircuitOpen(f"circuit open for {self.name}")
        if s == "half_open":
            if self._trial_in_flight:
                raise CircuitOpen(f"circuit half-open for {self.name}; a trial call is already running")
            self._trial_in_flight = True

    def record_success(self) -> None:
        self.failures = 0
        self.opened_at = None
        self._trial_in_flight = False

    def record_failure(self) -> None:
        self._trial_in_flight = False
        self.failures += 1
        if self.opened_at is not None or self.failures >= self.threshold:
            tripped = self.opened_at is None
            self.opened_at = self._clock()
            if tripped and self._on_open:
                self._on_open(self.name)
