#!/usr/bin/env python3
"""Import Cursor agent transcripts into a memsearch daily-journal memory dir.

Каждая реплика пересказывается тем же промптом memsearch и моделью haiku, что и
в хуке Stop, затем пересказы дописываются в дневные журналы memory/YYYY-MM-DD.md.

Usage:
  cursor_memsearch_import.py count     <cursor_dir> <copy_dir> <cache_dir> <memory_dir>
  cursor_memsearch_import.py sync      <cursor_dir> <copy_dir>
  cursor_memsearch_import.py summarize <cursor_dir> <copy_dir> <cache_dir> <memory_dir> [--limit N] [--jobs N] [--ru]
  cursor_memsearch_import.py assemble  <cursor_dir> <copy_dir> <cache_dir> <memory_dir>

BaoCode (docs/fork.md, lib/integrations/cursor_import/) runs it: sync, then
summarize, then assemble; count says how many turns are still to be told in
short ("N turns"), CLAUDE_BIN which Claude Code tells them.

- cursor_dir — ~/.cursor/projects/<проект>/agent-transcripts; copy_dir — его
  копия в проекте (.memsearch/cursor-transcripts). sync докладывает в копию
  новое и изменённое, ничего не удаляя, так что сессии, которые Cursor удалил,
  остаются. В журналах ссылки ведут на копию, а не в папку Cursor.
- Повторный запуск дописывает только новое: реплика, чья метка
  `session:<id> turn:L<строка>` уже есть в журнале (или `turn:line-<строка>`
  ручного импорта), не пересказывается и не пишется снова. Готовые пересказы
  лежат в cache_dir.
- Реплики без ответа и без действий агента пропускаются: пересказывать нечего.
- Если у подписки кончился лимит, summarize останавливается с ошибкой; сделанное
  остаётся в cache_dir, следующий запуск продолжит.
- --ru — писать по-русски всегда, а не только когда вопрос пользователя на
  русском (нужно для служебных английских реплик Cursor вроде отчётов о
  фоновых задачах).
"""
import concurrent.futures as cf
import datetime as dt
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

CLAUDE = os.environ.get("CLAUDE_BIN") or os.path.expanduser("~/.local/bin/claude")
AGENT = "Cursor"
MAX_CHARS = 40000

TS_RE = re.compile(r"<timestamp>(.*?)</timestamp>", re.S)
UQ_RE = re.compile(r"<user_query>(.*?)</user_query>", re.S)
ATTACHED_RE = re.compile(r'<(?:code_selection|file|attached_file)[^>]*path="([^"]+)"')
MARK_RE = re.compile(r"session:(\S+) turn:(?:L|line-)(\d+)")
CYR = re.compile(r"[а-яА-ЯёЁ]")

FORCE_RU = False


class LimitHit(Exception):
    """The subscription's limit is reached: nothing more can be told now."""


def prompt_file():
    found = sorted(glob.glob(os.path.expanduser(
        "~/.claude/plugins/cache/memsearch-plugins/memsearch/*/prompts/summarize.txt")))
    if not found:
        sys.exit("memsearch's summarize prompt not found: is its plugin installed?")
    return found[-1]


def text_of(msg):
    content = msg.get("message", {}).get("content", [])
    if isinstance(content, str):
        return content
    return "\n".join(b.get("text", "") for b in content
                     if isinstance(b, dict) and b.get("type") == "text")


def parse_ts(s):
    # "Wednesday, Oct 21, 2026, 2:54 PM (UTC+7)"
    s = re.sub(r"\s*\(UTC[^)]*\)", "", s).strip()
    try:
        return dt.datetime.strptime(s, "%A, %b %d, %Y, %I:%M %p")
    except ValueError:
        return None


def sessions(cursor_dir, copy_dir):
    """Each session: (id, the file to read, the copy's path the journal links).

    Cursor's file is read while it is there (the copy may lag behind it); the
    copy alone once Cursor dropped the session."""
    found = {}
    for base in (copy_dir, cursor_dir):
        for path in glob.glob(os.path.join(base, "*", "*.jsonl")):
            sid = os.path.basename(path)[:-6]
            found[sid] = path
    return [(sid, path, os.path.join(copy_dir, sid, sid + ".jsonl"))
            for sid, path in sorted(found.items())]


def clean_query(text, root):
    """The user's words, and what came with them: files, images, terminal."""
    q = UQ_RE.search(text)
    body = q.group(1).strip() if q else TS_RE.sub("", text).strip()
    extras = []
    paths = list(dict.fromkeys(p.replace(root + "/", "") for p in ATTACHED_RE.findall(text)))
    if paths:
        extras.append("[Attached]: " + ", ".join(paths))
    if "<image_files>" in text:
        extras.append("[Images attached]")
    if "<terminal_selection" in text:
        extras.append("[Terminal output attached]")
    return body + ("\n" + "\n".join(extras) if extras else "")


def load_turns(path, root):
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
                if not UQ_RE.search(t):
                    if turns and t.strip():
                        turns[-1]["parts"].append(f"[User]: {t.strip()[:2000]}")
                    continue
                m = TS_RE.search(t)
                query = clean_query(t, root)
                turns.append({
                    "line": lineno,
                    "ts": parse_ts(m.group(1)) if m else None,
                    "query": query,
                    "parts": [f"[User]: {query}"],
                    "answered": False,
                    "edited": [], "wrote": [], "deleted": [], "shells": 0, "other": set(),
                })
            elif role == "assistant" and turns:
                turn = turns[-1]
                content = (o.get("message") or {}).get("content") or []
                if isinstance(content, str):
                    content = [{"type": "text", "text": content}]
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text" and b.get("text", "").strip():
                        turn["parts"].append(f"[{AGENT}]: {b['text'].strip()}")
                        turn["answered"] = True
                    elif b.get("type") == "tool_use":
                        name = b.get("name")
                        target = ((b.get("input") or {}).get("path") or "").replace(root + "/", "")
                        if name in ("StrReplace", "StrictReplace", "Edit", "MultiEdit"):
                            turn["edited"].append(target)
                        elif name == "Write":
                            turn["wrote"].append(target)
                        elif name == "Delete":
                            turn["deleted"].append(target)
                        elif name == "Shell":
                            turn["shells"] += 1
                        elif name in ("Task", "WebSearch", "WebFetch", "CallMcpTool", "CreatePlan"):
                            turn["other"].add(name)
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


def acted(turn):
    return bool(turn["edited"] or turn["wrote"] or turn["deleted"] or turn["shells"])


def format_turn(turn):
    body = "\n\n".join(turn["parts"])
    if len(body) > MAX_CHARS:
        half = MAX_CHARS // 2
        body = body[:half] + "\n\n[... truncated ...]\n\n" + body[-half:]
    acts = []
    for label, items in (("edited", turn["edited"]), ("wrote", turn["wrote"]),
                         ("deleted", turn["deleted"])):
        unique = list(dict.fromkeys(x for x in items if x))
        if unique:
            more = f" (+{len(unique) - 25} more)" if len(unique) > 25 else ""
            acts.append(f"{label}: " + ", ".join(unique[:25]) + more)
    if turn["shells"]:
        acts.append(f"ran {turn['shells']} shell commands")
    if turn["other"]:
        acts.append("used " + ", ".join(sorted(turn["other"])))
    if acts:
        body += "\n\n[Tool activity]: " + "; ".join(acts)
    return f"=== Transcript of a conversation between User and {AGENT} ===\n{body}"


def imported(memdir):
    """The turns the journals have already: (session, line)."""
    marks = set()
    for path in glob.glob(os.path.join(memdir, "*.md")):
        with open(path, encoding="utf-8", errors="replace") as f:
            for sid, line in MARK_RE.findall(f.read()):
                marks.add((sid, int(line)))
    return marks


def project_root(memdir):
    # <root>/.memsearch/memory
    return os.path.dirname(os.path.dirname(os.path.abspath(memdir)))


def entries(cursor_dir, copy_dir, memdir):
    """The turns to bring: answered or acted on, not in the journals yet."""
    root = project_root(memdir)
    done = imported(memdir)
    out = []
    for sid, path, link in sessions(cursor_dir, copy_dir):
        for t in load_turns(path, root):
            if (sid, t["line"]) in done or not (t["answered"] or acted(t)):
                continue
            out.append((sid, link, t))
    return out


def cache_file(cache, sid, turn):
    return os.path.join(cache, f"{sid}_L{turn['line']}.md")


def pending(cursor_dir, copy_dir, cache, memdir):
    return [(sid, t) for sid, _, t in entries(cursor_dir, copy_dir, memdir)
            if not os.path.exists(cache_file(cache, sid, t))]


def summarize(text, prompt, query, cwd):
    want_ru = FORCE_RU or bool(CYR.search(query))
    for model in ("haiku", "haiku", "sonnet"):
        out = summarize_once(text, prompt, model, want_ru, cwd)
        if not want_ru or len(CYR.findall(out)) > len(out) // 4:
            return out
    raise RuntimeError("summary not in Russian after retries")


def summarize_once(text, prompt, model, want_ru, cwd):
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
        cwd=cwd)
    out = r.stdout.strip()
    if "hit your limit" in out:
        raise LimitHit(out[:200])
    if r.returncode != 0 or not out or out.startswith("API Error:"):
        raise RuntimeError(f"rc={r.returncode} out={out[:200]} err={r.stderr[:200]}")
    return out


def cmd_count(cursor_dir, copy_dir, cache, memdir):
    print(f"{len(pending(cursor_dir, copy_dir, cache, memdir))} turns", flush=True)


def cmd_sync(cursor_dir, copy_dir):
    os.makedirs(copy_dir, exist_ok=True)
    if os.path.isdir(cursor_dir):
        if shutil.which("rsync"):
            subprocess.run(["rsync", "-a", "--exclude", ".DS_Store",
                            cursor_dir.rstrip("/") + "/", copy_dir.rstrip("/") + "/"],
                           check=True)
        else:
            shutil.copytree(cursor_dir, copy_dir, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns(".DS_Store"))
    count = len(glob.glob(os.path.join(copy_dir, "*", "*.jsonl")))
    print(f"synced {count} sessions into {copy_dir}", flush=True)


def cmd_summarize(cursor_dir, copy_dir, cache, memdir, limit, jobs):
    os.makedirs(cache, exist_ok=True)
    prompt = open(prompt_file(), encoding="utf-8").read().replace("{{AGENT_NAME}}", AGENT)
    todo = pending(cursor_dir, copy_dir, cache, memdir)
    if limit:
        todo = todo[:limit]
    print(f"{len(todo)} turns to summarize", flush=True)
    # A neutral folder for claude -p: not the project, whose hooks and
    # settings would come in.
    cwd = tempfile.mkdtemp(prefix="cursor-import-")

    def work(item):
        sid, turn = item
        s = summarize(format_turn(turn), prompt, turn["query"], cwd)
        with open(cache_file(cache, sid, turn), "w", encoding="utf-8") as f:
            f.write(s + "\n")

    done = failed = 0
    limit_hit = None
    try:
        with cf.ThreadPoolExecutor(jobs) as ex:
            futs = {ex.submit(work, it): it for it in todo}
            for fu in cf.as_completed(futs):
                try:
                    fu.result()
                    done += 1
                except cf.CancelledError:
                    continue
                except LimitHit as e:
                    limit_hit = str(e)
                    ex.shutdown(cancel_futures=True)
                    break
                except Exception as e:
                    failed += 1
                    sid, turn = futs[fu]
                    print(f"FAIL {sid}_L{turn['line']}: {e}", flush=True)
                print(f"progress {done + failed}/{len(todo)} (failed {failed})", flush=True)
    finally:
        shutil.rmtree(cwd, ignore_errors=True)
    if limit_hit:
        print(f"limit reached after {done} turns: {limit_hit}", flush=True)
        sys.exit(3)
    print(f"done {done}, failed {failed}", flush=True)


def write_atomically(path, text):
    fd, temp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".cursor-import-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(temp, path)


def cmd_assemble(cursor_dir, copy_dir, cache, memdir):
    os.makedirs(memdir, exist_ok=True)
    by_day = {}
    unsummarized = 0
    for sid, link, t in entries(cursor_dir, copy_dir, memdir):
        summary_file = cache_file(cache, sid, t)
        if not os.path.exists(summary_file):
            unsummarized += 1
            continue
        with open(summary_file, encoding="utf-8") as f:
            summary = f.read().strip()
        if summary:
            by_day.setdefault(t["ts"].strftime("%Y-%m-%d"), []).append((sid, link, t, summary))

    written = 0
    for day, items in sorted(by_day.items()):
        items.sort(key=lambda e: (e[2]["ts"], e[0], e[2]["line"]))
        out = [""]
        seen = set()
        for sid, link, t, summary in items:
            ts = t["ts"]
            if sid not in seen:
                seen.add(sid)
                out.append(f"## Session {ts:%H:%M} (Cursor)\n")
            out.append(f"### {ts:%H:%M}" + (" (approx.)" if t.get("approx") else ""))
            out.append(f"<!-- session:{sid} turn:L{t['line']} source:cursor transcript:{link} -->")
            out.append(summary)
            out.append("")
        block = "\n".join(out) + "\n"
        path = os.path.join(memdir, f"{day}.md")
        existing = ""
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                existing = f.read()
        # A day's Cursor sessions came before its Claude Code ones: first,
        # unless Cursor's are there already, then after them all.
        if "source:cursor" in existing:
            text = existing.rstrip("\n") + "\n" + block
        else:
            text = block + existing
        write_atomically(path, text)
        written += len(items)
        print(f"{day}: {len(items)} turns, {len(seen)} sessions", flush=True)
    print(f"wrote {written} turns into {len(by_day)} days; "
          f"not summarized yet: {unsummarized}", flush=True)


def arg(a, name, default):
    return int(a[a.index(name) + 1]) if name in a else default


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "count":
        cmd_count(a[1], a[2], a[3], a[4])
    elif a[0] == "sync":
        cmd_sync(a[1], a[2])
    elif a[0] == "summarize":
        FORCE_RU = "--ru" in a
        cmd_summarize(a[1], a[2], a[3], a[4], arg(a, "--limit", 0), arg(a, "--jobs", 6))
    elif a[0] == "assemble":
        cmd_assemble(a[1], a[2], a[3], a[4])
    else:
        sys.exit(f"unknown command: {a[0]}")
