"""Heading-aware chunking. Never splits mid-sentence (except a single sentence far above the limit)."""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass

from .loaders import Section

_SENT = re.compile(r"(?<=[.!?।])\s+|\n+")


def estimate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


@dataclass
class RawChunk:
    text: str
    section: str
    page: int | None


def _split_sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENT.split(text) if s.strip()]


def _hard_split(sentence: str, max_chars: int) -> list[str]:
    words, out, cur = sentence.split(), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > max_chars:
            out.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}".strip()
    if cur:
        out.append(cur)
    return out


def chunk_section(sec: Section, target_tokens: int, overlap_tokens: int) -> list[RawChunk]:
    target_chars = target_tokens * 4
    overlap_chars = overlap_tokens * 4
    header = sec.heading.strip()

    def make(body: str) -> RawChunk:
        text = f"{header}\n{body}" if header else body
        return RawChunk(text=text, section=header, page=sec.page)

    if len(sec.text) <= target_chars:
        return [make(sec.text)]

    sentences: list[str] = []
    for s in _split_sentences(sec.text):
        sentences.extend(_hard_split(s, target_chars) if len(s) > target_chars * 2 else [s])

    chunks: list[RawChunk] = []
    cur: list[str] = []
    cur_len = 0
    for s in sentences:
        if cur and cur_len + len(s) + 1 > target_chars:
            chunks.append(make(" ".join(cur)))
            # carry the last whole sentences (up to overlap_chars) into the next chunk
            tail: list[str] = []
            n = 0
            for prev in reversed(cur):
                if n + len(prev) + 1 > overlap_chars:
                    break
                tail.insert(0, prev)
                n += len(prev) + 1
            cur, cur_len = tail, n
        cur.append(s)
        cur_len += len(s) + 1
    if cur:
        chunks.append(make(" ".join(cur)))
    return chunks


def chunk_id(scheme_id: str, source: str, text: str) -> str:
    return hashlib.sha256(f"{scheme_id}\x00{source}\x00{text}".encode()).hexdigest()
