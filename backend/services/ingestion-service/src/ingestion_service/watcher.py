from __future__ import annotations

import logging

from watchfiles import awatch

from .ingest import Ingestor

log = logging.getLogger("ingestion_service")


async def watch_forever(ingestor: Ingestor) -> None:
    """Re-ingest whenever files in the documents folder change (debounced by watchfiles)."""
    log.info("watching %s", ingestor.root)
    async for _changes in awatch(str(ingestor.root), debounce=2000):
        st = await ingestor.run()
        log.info("re-ingested after change: +%s -%s errors=%s", st.chunks_added, st.chunks_deleted, len(st.errors))
