from ingestion_service.embedding_client import EmbeddingError


async def test_embedding_breaker_opens_and_fails_fast(make, embedder, docs):
    ing = make()
    embedder.fail = True
    errors = []
    for _ in range(5):
        try:
            await ing.embedder.embed(["x"])
        except EmbeddingError as e:
            errors.append(str(e))
    assert all("returned 503" in e for e in errors) and ing.embedder.breaker.state == "open"
    calls = embedder.calls
    try:
        await ing.embedder.embed(["x"])
        raise AssertionError("expected failure")
    except EmbeddingError as e:
        assert "circuit open" in str(e) and embedder.calls == calls

    embedder.fail = False
    ing.embedder.breaker.opened_at -= 100
    vectors, _, _ = await ing.embedder.embed(["x"])
    assert len(vectors) == 1 and ing.embedder.breaker.state == "closed"


async def test_run_metrics(make, docs):
    (docs / "a.md").write_text('---\nscheme_id: "a"\nname: "A"\n---\n## S\ntext here')
    ing = make()
    await ing.run()
    text = ing.metrics.render()
    assert 'ingest_runs_total{state="done"} 1' in text and "ingest_chunks_added_total 1" in text and "ingest_file_errors_total 0" in text
