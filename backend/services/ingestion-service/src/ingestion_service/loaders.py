"""File loaders: turn a file into (front-matter, [Section]). Pluggable by extension."""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

SUPPORTED = {".md", ".txt", ".pdf", ".docx", ".html", ".htm"}


@dataclass
class Section:
    heading: str
    text: str
    page: int | None = None


@dataclass
class Loaded:
    front_matter: dict[str, Any] | None
    sections: list[Section]


_FM = re.compile(r"\A---\s*\n(.*?)\n---\s*\n?", re.DOTALL)
_HEADING = re.compile(r"^(#{1,6})\s+(.*\S)\s*$", re.MULTILINE)


def split_front_matter(text: str) -> tuple[dict[str, Any] | None, str]:
    m = _FM.match(text)
    if not m:
        return None, text
    try:
        data = yaml.safe_load(m.group(1))
    except yaml.YAMLError:
        return None, text
    if not isinstance(data, dict):
        return None, text
    return data, text[m.end():]


def sections_from_markdown(body: str) -> list[Section]:
    """One section per ## / ### heading; text before the first heading gets the title (# ...) or ''."""
    matches = list(_HEADING.finditer(body))
    if not matches:
        t = body.strip()
        return [Section("", t)] if t else []
    out: list[Section] = []
    title = ""
    pre = body[: matches[0].start()].strip()
    # first H1 is treated as the document title, prepended context for the intro
    if matches[0].group(1) == "#":
        title = matches[0].group(2).strip()
        matches = matches[1:]
    if pre:
        out.append(Section(title, pre))
    boundaries = [(m.group(2).strip(), m.end()) for m in matches]
    starts = [m.start() for m in matches] + [len(body)]
    for i, (head, content_start) in enumerate(boundaries):
        text = body[content_start : starts[i + 1]].strip()
        if text:
            out.append(Section(head, text))
    if not out and title:
        out.append(Section(title, title))
    return out


def load_md(path: Path) -> Loaded:
    fm, body = split_front_matter(path.read_text(encoding="utf-8", errors="replace"))
    return Loaded(fm, sections_from_markdown(body))


def load_txt(path: Path) -> Loaded:
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    return Loaded(None, [Section("", text)] if text else [])


def load_pdf(path: Path) -> Loaded:
    from pypdf import PdfReader

    reader = PdfReader(str(path))
    out = []
    for i, page in enumerate(reader.pages, start=1):
        t = (page.extract_text() or "").strip()
        if t:
            out.append(Section(f"page {i}", t, page=i))
    return Loaded(None, out)


def load_docx(path: Path) -> Loaded:
    import docx

    d = docx.Document(str(path))
    sections: list[Section] = []
    head, buf = "", []
    for p in d.paragraphs:
        txt = p.text.strip()
        if not txt:
            continue
        if (p.style.name or "").lower().startswith(("heading", "title")):
            if buf:
                sections.append(Section(head, "\n".join(buf)))
                buf = []
            head = txt
        else:
            buf.append(txt)
    if buf:
        sections.append(Section(head, "\n".join(buf)))
    return Loaded(None, sections)


def load_html(path: Path) -> Loaded:
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(path.read_text(encoding="utf-8", errors="replace"), "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "header", "aside", "noscript", "form"]):
        tag.decompose()
    root = soup.body or soup
    sections: list[Section] = []
    head, buf = "", []
    for el in root.find_all(["h1", "h2", "h3", "p", "li", "td", "th", "pre"]):
        txt = " ".join(el.get_text(" ", strip=True).split())
        if not txt:
            continue
        if el.name in {"h1", "h2", "h3"}:
            if buf:
                sections.append(Section(head, "\n".join(buf)))
                buf = []
            head = txt
        else:
            buf.append(txt)
    if buf:
        sections.append(Section(head, "\n".join(buf)))
    return Loaded(None, sections)


LOADERS = {".md": load_md, ".txt": load_txt, ".pdf": load_pdf, ".docx": load_docx, ".html": load_html, ".htm": load_html}


def load_file(path: Path) -> Loaded:
    return LOADERS[path.suffix.lower()](path)
