#!/usr/bin/env python3
"""Import Cursor agent transcripts into a memsearch daily-journal memory dir.

Каждая реплика пересказывается тем же промптом memsearch и моделью haiku, что и
в хуке Stop, затем пересказы раскладываются по дневным журналам memory/YYYY-MM-DD.md.

Usage:
  cursor_memsearch_import.py count     <transcripts_dir> <cache_dir>
  cursor_memsearch_import.py summarize <transcripts_dir> <cache_dir> [--limit N] [--jobs N] [--ru]
  cursor_memsearch_import.py assemble  <transcripts_dir> <cache_dir> <memory_dir>

BaoCode (docs/fork.md, lib/integrations/cursor_import/) runs it: count says how
many turns are still to be told in short ("N turns"), CLAUDE_BIN which Claude
Code tells them.

summarize можно перезапускать: готовые пересказы из cache_dir не пересчитываются.
--ru — писать по-русски всегда, а не только когда вопрос пользователя на русском
(нужно для служебных английских реплик Cursor вроде отчётов о фоновых задачах).
"""
import concurrent.futures as cf
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

CLAUDE = os.environ.get("CLAUDE_BIN") or os.path.expanduser("~/.local/bin/claude")


def prompt_file():
    found = sorted(glob.glob(os.path.expanduser(
        "~/.claude/plugins/cache/memsearch-plugins/memsearch/*/prompts/summarize.txt")))
    if not found:
        sys.exit("memsearch's summarize prompt not found: is its plugin installed?")
    return found[-1]
AGENT = "Cursor"
MAX_CHARS = 40000

TS_RE = re.compile(r"<timestamp>(.*?)</timestamp>", re.S)
UQ_RE = re.compile(r"<user_query>(.*?)</user_query>", re.S)


def text_of(msg):
    content = msg.get("message", {}).get("content", [])
    if isinstance(content, str):
        return content
    return "\n".join(b.get("text", "") for b in content
                     if isinstance(b, dict) and b.get("type") == "text")


def parse_ts(s):
    # "Wednesday, Oct 21, 2026, 2:54 PM (UTC+7)"
    s = re.sub(r"\s*\(UTC[^)]*\)", "", s).strip()
    return dt.datetime.strptime(s, "%A, %b %d, %Y, %I:%M %p")


def load_turns(path):
    """Split a Cursor transcript into turns: user_query + following assistant msgs."""
    turns = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for lineno, line in enumerate(f, 1):
            try:
                o = json.loads(line)
            except Exception:
                continue
            role = o.get("role")
            if role == "user":
                t = text_of(o)
                q = UQ_RE.search(t)
                if not q:
                    if turns:
                        turns[-1]["parts"].append(f"[User]: {t.strip()[:2000]}")
                    continue
                m = TS_RE.search(t)
                turns.append({
                    "line": lineno,
                    "ts": parse_ts(m.group(1)) if m else None,
                    "query": q.group(1).strip(),
                    "parts": [f"[User]: {q.group(1).strip()}"],
                })
            elif role == "assistant" and turns:
                t = text_of(o).strip()
                if t:
                    turns[-1]["parts"].append(f"[{AGENT}]: {t}")
    # Старые сессии Cursor (до ~мая 2026) не пишут <timestamp>. Ведущие реплики
    # без времени получают время из файла: равномерно между созданием и последним
    # изменением сессии, по номеру строки. Остальные пропуски — время предыдущей.
    st = os.stat(path)
    born = dt.datetime.fromtimestamp(getattr(st, "st_birthtime", st.st_mtime))
    mtime = dt.datetime.fromtimestamp(st.st_mtime)
    first_known = next((t["ts"] for t in turns if t["ts"]), None)
    end = min(first_known, mtime) if first_known else mtime
    end = max(end, born)
    last_line = max((t["line"] for t in turns), default=1)
    prev = None  # последнее известное (не вычисленное) время
    for t in turns:
        if t["ts"] is None:
            t["approx"] = True
            t["ts"] = prev or born + (end - born) * (t["line"] / last_line)
        else:
            prev = t["ts"]
    return turns


def format_turn(turn):
    body = "\n\n".join(turn["parts"])
    if len(body) > MAX_CHARS:
        half = MAX_CHARS // 2
        body = body[:half] + "\n\n[... truncated ...]\n\n" + body[-half:]
    return f"=== Transcript of a conversation between User and {AGENT} ===\n{body}"


CYR = re.compile(r"[а-яА-ЯёЁ]")


FORCE_RU = False


def summarize(text, prompt, query):
    want_ru = FORCE_RU or bool(CYR.search(query))
    for model in ("haiku", "haiku", "sonnet"):
        out = summarize_once(text, prompt, model, want_ru)
        if not want_ru or len(CYR.findall(out)) > len(out) // 4:
            return out
    raise RuntimeError("summary not in Russian after retries")


def summarize_once(text, prompt, model, want_ru):
    env = dict(os.environ, MEMSEARCH_NO_WATCH="1", MEMSEARCH_DISABLE="1", CLAUDECODE="")
    if want_ru:
        prompt = "ВАЖНО: пиши все пункты на русском языке.\n\n" + prompt
    llm_input = (f"{prompt}\n\nTranscript:\n{text}\n\n=== End of transcript ===\n"
                 "Reminder: write the bullets in the language of the [User] text "
                 "(if User wrote in Russian, every bullet must be in Russian). "
                 "Output only the bullet points.")
    r = subprocess.run(
        [CLAUDE, "-p", "--strict-mcp-config", "--tools", "", "--model", model,
         "--no-session-persistence"],
        input=llm_input, capture_output=True, text=True, timeout=180, env=env,
        cwd="/tmp")
    out = r.stdout.strip()
    if r.returncode != 0 or not out or out.startswith(("API Error:", "You've hit your limit")):
        raise RuntimeError(f"rc={r.returncode} out={out[:200]} err={r.stderr[:200]}")
    return out


def sessions(tdir):
    return sorted(glob.glob(os.path.join(tdir, "*", "*.jsonl")))


def pending(tdir, cache):
    """The turns not told in short yet: (cache file, its text, its query)."""
    todo = []
    for path in sessions(tdir):
        sid = os.path.basename(path)[:-6]
        for t in load_turns(path):
            out = os.path.join(cache, f"{sid}_L{t['line']}.md")
            if not os.path.exists(out):
                todo.append((out, format_turn(t), t["query"]))
    return todo


def cmd_count(tdir, cache):
    print(f"{len(pending(tdir, cache))} turns", flush=True)


def cmd_summarize(tdir, cache, limit, jobs):
    os.makedirs(cache, exist_ok=True)
    prompt = open(prompt_file(), encoding="utf-8").read().replace("{{AGENT_NAME}}", AGENT)
    todo = []
    for path in sessions(tdir):
        sid = os.path.basename(path)[:-6]
        for t in load_turns(path):
            out = os.path.join(cache, f"{sid}_L{t['line']}.md")
            if not os.path.exists(out):
                todo.append((out, format_turn(t), t["query"]))
    if limit:
        todo = todo[:limit]
    print(f"{len(todo)} turns to summarize", flush=True)

    def work(item):
        out, text, query = item
        s = summarize(text, prompt, query)
        with open(out, "w", encoding="utf-8") as f:
            f.write(s + "\n")
        return out

    done = failed = 0
    with cf.ThreadPoolExecutor(jobs) as ex:
        futs = {ex.submit(work, it): it[0] for it in todo}
        for fu in cf.as_completed(futs):
            try:
                fu.result()
                done += 1
            except Exception as e:
                failed += 1
                print(f"FAIL {os.path.basename(futs[fu])}: {e}", flush=True)
            if (done + failed) % 10 == 0:
                print(f"progress {done + failed}/{len(todo)} (failed {failed})", flush=True)
    print(f"done {done}, failed {failed}", flush=True)


def cmd_assemble(tdir, cache, memdir):
    # Collect (ts, sid, turn) across all sessions, grouped by day
    entries = []
    for path in sessions(tdir):
        sid = os.path.basename(path)[:-6]
        for t in load_turns(path):
            entries.append((t["ts"], sid, t, path))
    entries.sort(key=lambda e: (e[0], e[1], e[2]["line"]))

    by_day = {}
    for e in entries:
        by_day.setdefault(e[0].strftime("%Y-%m-%d"), []).append(e)

    missing = 0
    for day, items in sorted(by_day.items()):
        out = []
        seen = set()
        out.append("")
        for ts, sid, t, path in items:
            if sid not in seen:
                seen.add(sid)
                out.append(f"## Session {ts:%H:%M} (Cursor)\n")
            out.append(f"### {ts:%H:%M}" + (" (время примерное)" if t.get("approx") else ""))
            out.append(f"<!-- session:{sid} turn:L{t['line']} source:cursor transcript:{path} -->")
            cf_ = os.path.join(cache, f"{sid}_L{t['line']}.md")
            if os.path.exists(cf_):
                out.append(open(cf_, encoding="utf-8").read().strip())
            else:
                missing += 1
                q = " ".join(t["query"].split())[:300]
                out.append(f"- User (Cursor): {q}\n- Memory summary unavailable; use the transcript anchor.")
            out.append("")
        block = "\n".join(out) + "\n"
        mf = os.path.join(memdir, f"{day}.md")
        existing = open(mf, encoding="utf-8").read() if os.path.exists(mf) else ""
        if "source:cursor" in existing:
            print(f"skip {day}: already contains Cursor import")
            continue
        # Cursor sessions predate the existing Claude Code entries: put them first
        with open(mf, "w", encoding="utf-8") as f:
            f.write(block + existing)
        print(f"{day}: {len(items)} turns, {len(seen)} sessions")
    print(f"missing summaries: {missing}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "count":
        cmd_count(a[1], a[2])
    elif a[0] == "summarize":
        limit = int(a[a.index("--limit") + 1]) if "--limit" in a else 0
        jobs = int(a[a.index("--jobs") + 1]) if "--jobs" in a else 6
        FORCE_RU = "--ru" in a
        cmd_summarize(a[1], a[2], limit, jobs)
    elif a[0] == "assemble":
        cmd_assemble(a[1], a[2], a[3])
