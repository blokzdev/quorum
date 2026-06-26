"""Per-run event log: assigns sequence numbers and fans events out to SSE subscribers.

A run's events are produced by a worker thread and consumed by zero or more SSE connections that may
attach late or reconnect. The log keeps every event in memory for ``Last-Event-ID`` replay and pushes
new events to live subscribers via the server's asyncio loop (thread-safe hand-off).

P0 keeps the log in memory only; SQLite durability (so a run survives a sidecar restart) is a planned
Phase-1 add — the ``append``/``replay_from`` surface is already shaped for it.
"""

from __future__ import annotations

import asyncio
import contextlib
import threading

from tradingagents.runtime.events import Event, EventType

_TERMINAL = (EventType.RUN_DONE, EventType.ERROR)


class EventLog:
    """Thread-safe, append-only log of a single run's events with live SSE fan-out."""

    def __init__(self, run_id: str):
        self.run_id = run_id
        self._events: list[Event] = []
        self._seq = 0
        self._lock = threading.Lock()
        self._subscribers: set[asyncio.Queue] = set()
        self._loop: asyncio.AbstractEventLoop | None = None
        self.terminal = False

    def append(self, event: Event) -> Event:
        """Stamp ``seq``/``run_id``, store, and notify live subscribers. Called from the worker thread."""
        with self._lock:
            event.seq = self._seq
            event.run_id = self.run_id
            self._seq += 1
            self._events.append(event)
            if event.type in _TERMINAL:
                self.terminal = True
            subscribers = list(self._subscribers)
            loop = self._loop
        if loop is not None:
            for q in subscribers:
                with contextlib.suppress(RuntimeError):  # loop closed -> subscriber gone
                    loop.call_soon_threadsafe(q.put_nowait, event)
        return event

    def replay_from(self, seq: int) -> list[Event]:
        """Snapshot of all events with ``seq >= seq`` (for Last-Event-ID resume)."""
        with self._lock:
            return [e for e in self._events if e.seq >= seq]

    def subscribe(self) -> asyncio.Queue:
        """Register a live subscriber. Must be called from within the server's event loop."""
        q: asyncio.Queue = asyncio.Queue()
        with self._lock:
            self._subscribers.add(q)
            if self._loop is None:
                self._loop = asyncio.get_running_loop()
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        with self._lock:
            self._subscribers.discard(q)

    @property
    def last_seq(self) -> int:
        with self._lock:
            return self._seq - 1
