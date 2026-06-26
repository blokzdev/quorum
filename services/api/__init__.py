"""Quorum local API sidecar: a FastAPI + SSE boundary over the TradingAgents engine.

Runs on 127.0.0.1 with a per-launch bearer token. A run is a server-owned, durable job whose typed
events are streamed over SSE (with Last-Event-ID replay), so the desktop UI — and later a LAN/WAN
mobile remote over the identical API — is a reconnectable viewer, not the owner of the run.
"""
