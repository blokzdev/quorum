"""Per-job config + credential isolation for running multiple analyses in one process.

The engine reads a process-global config (``tradingagents.dataflows.config._config``) and resolves
provider API keys from ``os.environ`` at graph-construction time. To run isolated jobs (a FastAPI
sidecar, batch runs) without cross-contamination, :class:`JobIsolationContext` snapshots and restores
both around a job, mirroring the proven ``tests/conftest.py::_isolate_config`` reset — a **direct
deepcopy assignment** of ``DEFAULT_CONFIG`` (not ``set_config`` merge, which would leak keys from a
previous job).

Concurrency note: the global config and ``os.environ`` are process-wide, so jobs MUST NOT run
concurrently inside one process under this context — serialize them (the sidecar uses a single
worker / global lock). True parallelism needs a process per job.
"""

from __future__ import annotations

import copy
import os
from typing import Any

import tradingagents.dataflows.config as _config_module
import tradingagents.default_config as _default_config
from tradingagents.llm_clients.api_key_env import PROVIDER_API_KEY_ENV

# Data-vendor keys that aren't LLM providers (read at tool-call time from os.environ).
_VENDOR_API_KEY_ENV: dict[str, str] = {
    "fred": "FRED_API_KEY",
    "alpha_vantage": "ALPHA_VANTAGE_API_KEY",
}


def build_api_keys_dict(provider_keys: dict[str, str]) -> dict[str, str]:
    """Map ``{provider_or_vendor: key}`` to ``{ENV_VAR: key}`` for environment injection.

    Unknown names and empty keys are skipped. Example::

        build_api_keys_dict({"openai": "sk-…", "fred": "abc"})
        # -> {"OPENAI_API_KEY": "sk-…", "FRED_API_KEY": "abc"}
    """
    env: dict[str, str] = {}
    for name, key in provider_keys.items():
        if not key:
            continue
        env_var = PROVIDER_API_KEY_ENV.get(name.lower()) or _VENDOR_API_KEY_ENV.get(name.lower())
        if env_var:
            env[env_var] = key
    return env


class JobIsolationContext:
    """Snapshot/restore the global config and selected env keys around one job.

    Build the graph **inside** the context — LLM clients read their keys from ``os.environ`` at
    construction time, so the keys must be installed first::

        with JobIsolationContext(job_config, env_keys):
            graph = TradingAgentsGraph(analysts, config=job_config)
            run_streaming(graph, ...)
    """

    def __init__(
        self,
        job_config: dict[str, Any] | None = None,
        env_keys: dict[str, str] | None = None,
    ):
        self.job_config = job_config or {}
        self.env_keys = env_keys or {}
        self._saved_config: dict | None = None
        self._saved_env: dict[str, str | None] = {}

    def __enter__(self) -> JobIsolationContext:
        # Snapshot, then reset to a pristine DEFAULT_CONFIG and apply this job's overrides.
        self._saved_config = copy.deepcopy(_config_module._config)
        _config_module._config = copy.deepcopy(_default_config.DEFAULT_CONFIG)
        if self.job_config:
            _config_module.set_config(self.job_config)
        # Inject per-job keys, remembering the prior value (None = was unset) for restore.
        for env_var, value in self.env_keys.items():
            self._saved_env[env_var] = os.environ.get(env_var)
            os.environ[env_var] = value
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        _config_module._config = self._saved_config
        for env_var, original in self._saved_env.items():
            if original is None:
                os.environ.pop(env_var, None)
            else:
                os.environ[env_var] = original
        return False  # never suppress exceptions
