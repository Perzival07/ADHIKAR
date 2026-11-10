from __future__ import annotations

from collections import Counter

from haqdaar_common import Registry


class Metrics:
    """Counters used by the pipeline. Mirrored into the Prometheus registry as reco_<name>."""

    def __init__(self, registry: Registry | None = None) -> None:
        self.c: Counter[str] = Counter()
        self.registry = registry or Registry()
        self._stage = self.registry.histogram("reco_stage_seconds", "Pipeline stage latency", ("stage",))

    def inc(self, name: str, n: int = 1) -> None:
        self.c[name] += n
        metric = f"reco_{name}" if name.endswith("_total") else f"reco_{name}_total"
        self.registry.counter(metric, name.replace("_", " ")).inc(n)

    def observe_stage(self, stage: str, seconds: float) -> None:
        self._stage.observe(seconds, stage=stage)
