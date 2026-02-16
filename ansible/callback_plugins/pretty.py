# -*- coding: utf-8 -*-
"""Rich terminal output callback plugin for Ansible.

Renders playbook output with colors, Unicode symbols, and Rich tables.
Replaces the default stdout callback with compact, scannable output.

Verbosity levels:
    (none)  Compact one-liners, skipped tasks hidden
    -v      Show skipped tasks, changed details, command stdout
    -vv     Full Rich Pretty-printed result dicts
    -vvv    Full result + task metadata (path, action, args)
"""
from __future__ import annotations

import re
from datetime import datetime, timezone

from ansible import constants as C
from ansible.plugins.callback import CallbackBase

try:
    from rich.console import Console
    from rich.markup import escape
    from rich.padding import Padding
    from rich.panel import Panel
    from rich.pretty import Pretty
    from rich.table import Table
    from rich.theme import Theme

    HAS_RICH = True
except ImportError:
    HAS_RICH = False


DOCUMENTATION = """
    name: pretty
    type: stdout
    short_description: Rich terminal-inspired output
    description:
        - Compact, colored output using the Rich library.
        - Symbols for task status, module-aware brief extraction.
        - Configurable via Ansible verbosity flags (-v, -vv, -vvv).
    requirements:
        - rich (pip install rich)
"""

# ── Symbols ──────────────────────────────────────────────────────

SYM_OK = "\u2713"       # ✓
SYM_CHANGED = "\u25cf"  # ●
SYM_FAILED = "\u2717"   # ✗
SYM_SKIPPED = "\u25cb"  # ○
SYM_INCLUDED = "\u2192" # →

# ── Theme ────────────────────────────────────────────────────────

THEME = Theme(
    {
        "ok": "green",
        "changed": "yellow",
        "failed": "bold red",
        "skipped": "cyan",
        "unreachable": "bold red",
        "included": "dim",
        "detail": "dim white",
        "handler_prefix": "bold magenta",
        "task_name": "white",
    }
)

# ── Modules whose result dict should be suppressed ───────────────

_SUPPRESS_RESULT_ACTIONS = frozenset(
    [
        "ansible.builtin.set_fact",
        "set_fact",
        "ansible.builtin.include_tasks",
        "include_tasks",
        "ansible.builtin.include_role",
        "include_role",
        "ansible.builtin.import_tasks",
        "import_tasks",
        "ansible.builtin.import_role",
        "import_role",
        "ansible.builtin.meta",
        "meta",
    ]
)

_SERVICE_ACTIONS = frozenset(
    [
        "ansible.builtin.systemd",
        "ansible.builtin.systemd_service",
        "ansible.builtin.service",
        "systemd",
        "systemd_service",
        "service",
    ]
)

_PACKAGE_ACTIONS = frozenset(
    [
        "community.general.pacman",
        "pacman",
        "ansible.builtin.package",
        "package",
        "ansible.builtin.apt",
        "apt",
        "ansible.builtin.dnf",
        "dnf",
        "ansible.builtin.yum",
        "yum",
    ]
)

# ── ASCII table detection ────────────────────────────────────────

_TABLE_BORDER_RE = re.compile(r"^\+[-+]+\+$")
_TABLE_ROW_RE = re.compile(r"^\|(.+)\|$")

# Generic messages from Ansible internals that add no information
_NOISE_MSGS = frozenset(
    [
        "All items completed",
        "All paths examined",
        "All assertions passed",
    ]
)
_NOISE_PATTERNS = (
    re.compile(r"^non-zero return code$"),
    re.compile(r"^Skipped, no items found in loop\b"),
)


def _is_noise_msg(msg: str) -> bool:
    """Return True if msg is generic Ansible internals noise."""
    if msg in _NOISE_MSGS:
        return True
    return any(p.search(msg) for p in _NOISE_PATTERNS)


class CallbackModule(CallbackBase):
    """Rich stdout callback for Ansible."""

    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "pretty"
    CALLBACK_NEEDS_ENABLED = False

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if HAS_RICH:
            self.console = Console(theme=THEME, highlight=False, soft_wrap=True)
        else:
            self.console = None
        self._is_handler = False
        self._play_start_time = None
        self._task_name = ""
        self._loop_items_ok = 0
        self._loop_items_changed = 0
        self._loop_items_failed = 0

    # ── Helpers ──────────────────────────────────────────────────

    def _print(self, msg, **kwargs):
        """Print via Rich console, or fallback to display."""
        if self.console:
            self.console.print(msg, **kwargs)
        else:
            plain = msg if isinstance(msg, str) else str(msg)
            self._display.display(plain)

    def _format_task_line(self, symbol, style, name, detail=""):
        """Format a single task status line."""
        prefix = ""
        if self._is_handler:
            prefix = "[handler_prefix]HANDLER[/handler_prefix] "

        name_escaped = escape(name) if HAS_RICH else name
        detail_escaped = escape(str(detail)) if HAS_RICH and detail else ""

        if detail_escaped:
            pad = max(1, 50 - len(name))
            spacing = " " * pad
            return f"  {prefix}[{style}]{symbol}[/{style}] [task_name]{name_escaped}[/task_name]{spacing}[detail]{detail_escaped}[/detail]"
        return f"  {prefix}[{style}]{symbol}[/{style}] [task_name]{name_escaped}[/task_name]"

    def _extract_brief(self, result):
        """Extract a short summary string from the task result."""
        action = result._task.action
        r = result._result

        # Debug: show msg content
        if action in ("ansible.builtin.debug", "debug"):
            msg = r.get("msg", "")
            if isinstance(msg, list):
                return None  # handled separately by _print_debug_msg
            if isinstance(msg, str) and len(msg) < 100:
                return msg
            return ""

        # Suppress noisy modules
        if action in _SUPPRESS_RESULT_ACTIONS:
            return ""

        # Services: just show state
        if action in _SERVICE_ACTIONS:
            state = r.get("state", "")
            name = r.get("name", "")
            if name and state:
                return f"{name}: {state}"
            return state or ""

        # Packages: show count
        if action in _PACKAGE_ACTIONS:
            pkgs = r.get("packages", [])
            if pkgs:
                return f"{len(pkgs)} package(s)"
            return r.get("msg", "")

        # Downloads: show file size
        if action in ("ansible.builtin.get_url", "get_url"):
            size = r.get("size", 0)
            if size:
                return f"{size / 1048576:.1f} MB"
            return ""

        # File/template: show dest
        if action in (
            "ansible.builtin.copy",
            "copy",
            "ansible.builtin.template",
            "template",
            "ansible.builtin.file",
            "file",
        ):
            dest = r.get("dest", r.get("path", ""))
            state = r.get("state", "")
            if dest:
                return f"{dest}" + (f" ({state})" if state else "")
            return ""

        # Command/shell: prefer short stdout over generic msg
        if action in (
            "ansible.builtin.command",
            "command",
            "ansible.builtin.shell",
            "shell",
        ):
            stdout = r.get("stdout", "").strip()
            if stdout and "\n" not in stdout and len(stdout) < 80:
                return stdout
            msg = r.get("msg", "")
            if msg and isinstance(msg, str) and len(msg) < 80:
                return msg
            return ""

        # Assert: show msg
        if action in ("ansible.builtin.assert", "assert"):
            return r.get("msg", "")

        # Generic: short msg if available — but suppress common noise
        if "msg" in r and isinstance(r["msg"], str) and len(r["msg"]) < 80:
            msg = r["msg"]
            if msg and not _is_noise_msg(msg):
                return msg

        return ""

    def _print_debug_msg(self, msg):
        """Print debug message content — detect ASCII tables and render as Rich Table."""
        if isinstance(msg, list):
            # Check if this is an ASCII-art table
            if len(msg) >= 3 and _TABLE_BORDER_RE.match(str(msg[0])):
                self._render_ascii_table(msg)
                return
            # Just print lines
            for line in msg:
                self._print(f"      [detail]{escape(str(line))}[/detail]")
        elif isinstance(msg, str):
            for line in msg.split("\n"):
                self._print(f"      [detail]{escape(line)}[/detail]")

    def _render_ascii_table(self, lines):
        """Convert ASCII +---+---+ table to Rich Table."""
        table = Table(show_header=True, padding=(0, 1))
        header_found = False

        for line in lines:
            s = str(line).strip()
            if _TABLE_BORDER_RE.match(s):
                continue
            m = _TABLE_ROW_RE.match(s)
            if m:
                cells = [c.strip() for c in m.group(1).split("|")]
                if not header_found:
                    for cell in cells:
                        style = "bold" if not header_found else ""
                        table.add_column(cell, style=style)
                    header_found = True
                else:
                    table.add_row(*cells)

        self._print(Padding(table, (0, 0, 0, 4)))

    def _print_verbose_result(self, result):
        """Print full result at -vv or higher."""
        if not HAS_RICH:
            self._print(self._dump_results(result._result, indent=4))
            return

        cleaned = self._clean_results(result._result, result._task.action)
        if cleaned is None:
            cleaned = dict(result._result)
        # Remove noisy keys
        for key in ("_ansible_verbose_always", "_ansible_verbose_override",
                     "_ansible_no_log", "invocation"):
            cleaned.pop(key, None)

        if self._display.verbosity >= 3:
            task = result._task
            self._print(f"      [dim]action: {task.action}[/dim]")
            if hasattr(task, "_role") and task._role:
                self._print(f"      [dim]role: {task._role.get_name()}[/dim]")

        self._print(Padding(Pretty(cleaned, indent_guides=True), (0, 0, 0, 6)))

    # ── Playbook Events ─────────────────────────────────────────

    def v2_playbook_on_play_start(self, play):
        name = play.get_name().strip() or "Unnamed Play"
        self._play_start_time = datetime.now(tz=timezone.utc)
        self._is_handler = False

        if HAS_RICH:
            self._print(Panel(
                f"PLAY [{escape(name)}]",
                style="bold cyan",
                expand=True,
            ))
        else:
            self._print(f"\nPLAY [{name}] {'*' * 50}")

    def v2_playbook_on_task_start(self, task, is_conditional):
        self._task_name = task.get_name().strip()
        self._is_handler = False
        self._loop_items_ok = 0
        self._loop_items_changed = 0
        self._loop_items_failed = 0

    def v2_playbook_on_handler_task_start(self, task):
        self._task_name = task.get_name().strip()
        self._is_handler = True
        self._loop_items_ok = 0
        self._loop_items_changed = 0
        self._loop_items_failed = 0

    # ── Runner Events ────────────────────────────────────────────

    def v2_runner_on_ok(self, result):
        action = result._task.action
        name = self._task_name or result._task.get_name().strip()
        changed = result._result.get("changed", False)

        # Include tasks: dim arrow
        if action in _SUPPRESS_RESULT_ACTIONS and not changed:
            if action in (
                "ansible.builtin.include_tasks",
                "include_tasks",
                "ansible.builtin.include_role",
                "include_role",
                "ansible.builtin.import_tasks",
                "import_tasks",
                "ansible.builtin.import_role",
                "import_role",
            ):
                self._print(self._format_task_line(SYM_INCLUDED, "included", name))
                return
            # set_fact, meta — just show ok
            if self._display.verbosity < 1:
                self._print(self._format_task_line(SYM_OK, "ok", name))
                return

        # Extract brief (filter generic Ansible noise)
        brief = self._extract_brief(result)
        if brief and _is_noise_msg(brief):
            brief = ""

        if changed:
            sym, style = SYM_CHANGED, "changed"
        else:
            sym, style = SYM_OK, "ok"

        # Debug msg: special handling
        if action in ("ansible.builtin.debug", "debug"):
            msg = result._result.get("msg", "")
            if isinstance(msg, list):
                self._print(self._format_task_line(sym, style, name))
                self._print_debug_msg(msg)
                return
            if isinstance(msg, str) and msg and not _is_noise_msg(msg):
                # Short msg → inline detail
                if len(msg) < 60:
                    self._print(self._format_task_line(sym, style, name, msg))
                else:
                    self._print(self._format_task_line(sym, style, name))
                    self._print_debug_msg(msg)
                return

        self._print(self._format_task_line(sym, style, name, brief if brief else ""))

        # Show stdout for changed command/shell tasks (even at default verbosity)
        r = result._result
        if changed and action in ("ansible.builtin.command", "command",
                                  "ansible.builtin.shell", "shell"):
            stdout = r.get("stdout", "")
            if stdout:
                max_lines = 5 if self._display.verbosity >= 1 else 3
                for line in stdout.split("\n")[:max_lines]:
                    self._print(f"      [detail]{escape(line)}[/detail]")

        # Verbose: show full result
        if self._display.verbosity >= 2:
            self._print_verbose_result(result)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        name = self._task_name or result._task.get_name().strip()
        r = result._result

        if ignore_errors:
            style = "changed"
            sym = SYM_CHANGED
            label = "(ignored)"
        else:
            style = "failed"
            sym = SYM_FAILED
            label = "FAILED"

        self._print(self._format_task_line(sym, style, name, label))

        # Always show error details
        msg = r.get("msg", "")
        if msg:
            if isinstance(msg, str):
                for line in msg.split("\n"):
                    self._print(f"      [{style}]{escape(line)}[/{style}]")
            else:
                self._print(f"      [{style}]{escape(str(msg))}[/{style}]")

        stderr = r.get("stderr", "")
        if stderr:
            self._print(f"      [dim]stderr:[/dim]")
            for line in str(stderr).split("\n")[:10]:
                self._print(f"        [dim]{escape(line)}[/dim]")

        # Show full result at any verbosity for failures
        if self._display.verbosity >= 1:
            self._print_verbose_result(result)

    def v2_runner_on_skipped(self, result):
        if self._display.verbosity < 1:
            return

        name = self._task_name or result._task.get_name().strip()
        skip_reason = result._result.get("skip_reason", "")
        detail = ""
        if self._display.verbosity >= 1 and skip_reason and skip_reason != "Conditional result was False":
            detail = skip_reason

        self._print(self._format_task_line(SYM_SKIPPED, "skipped", name, detail))

    def v2_runner_on_unreachable(self, result):
        name = self._task_name or result._task.get_name().strip()
        msg = result._result.get("msg", "Host unreachable")
        self._print(self._format_task_line(SYM_FAILED, "unreachable", name, "UNREACHABLE"))
        self._print(f"      [unreachable]{escape(str(msg))}[/unreachable]")

    # ── Loop Items ───────────────────────────────────────────────

    def v2_runner_item_on_ok(self, result):
        if result._result.get("changed", False):
            self._loop_items_changed += 1
        else:
            self._loop_items_ok += 1

        # At -vv show each item
        if self._display.verbosity >= 2:
            item_label = self._get_item_label(result)
            changed = result._result.get("changed", False)
            sym = SYM_CHANGED if changed else SYM_OK
            style = "changed" if changed else "ok"
            self._print(f"    [{style}]{sym}[/{style}] [detail](item={escape(str(item_label))})[/detail]")

    def v2_runner_item_on_failed(self, result):
        self._loop_items_failed += 1
        item_label = self._get_item_label(result)
        msg = result._result.get("msg", "")
        self._print(f"    [failed]{SYM_FAILED}[/failed] [detail](item={escape(str(item_label))})[/detail]")
        if msg:
            self._print(f"      [failed]{escape(str(msg))}[/failed]")

    def v2_runner_item_on_skipped(self, result):
        if self._display.verbosity >= 2:
            item_label = self._get_item_label(result)
            self._print(f"    [skipped]{SYM_SKIPPED}[/skipped] [detail](item={escape(str(item_label))})[/detail]")

    def _get_item_label(self, result):
        """Get display label for loop item."""
        item = result._result.get("ansible_loop_var", "item")
        item_value = result._result.get(item, "")
        # Use loop_control label if available
        if isinstance(item_value, dict):
            # Try common label keys
            for key in ("name", "label", "id", "path"):
                if key in item_value:
                    return item_value[key]
            return str(item_value)[:50]
        return str(item_value)[:50]

    # ── Stats ────────────────────────────────────────────────────

    def v2_playbook_on_stats(self, stats):
        self._print("")

        if not HAS_RICH:
            self._print(f"\nPLAY RECAP {'*' * 50}")
            hosts = sorted(stats.processed.keys())
            for h in hosts:
                s = stats.summarize(h)
                self._print(
                    f"  {h}: ok={s['ok']} changed={s['changed']} "
                    f"unreachable={s['unreachable']} failed={s['failures']} "
                    f"skipped={s['skipped']} rescued={s['rescued']} "
                    f"ignored={s['ignored']}"
                )
            return

        # Rich Table recap
        table = Table(
            title="PLAY RECAP",
            show_header=True,
            title_style="bold",
            padding=(0, 1),
        )
        table.add_column("Host", style="bold", min_width=15)
        table.add_column(f"{SYM_OK} ok", style="ok", justify="right")
        table.add_column(f"{SYM_CHANGED} changed", style="changed", justify="right")
        table.add_column(f"{SYM_FAILED} failed", style="failed", justify="right")
        table.add_column(f"{SYM_SKIPPED} skipped", style="skipped", justify="right")
        table.add_column("rescued", style="ok", justify="right")
        table.add_column("ignored", style="changed", justify="right")

        hosts = sorted(stats.processed.keys())
        for h in hosts:
            s = stats.summarize(h)
            table.add_row(
                h,
                str(s["ok"]),
                str(s["changed"]),
                str(s["failures"]),
                str(s["skipped"]),
                str(s["rescued"]),
                str(s["ignored"]),
            )

        self._print(table)

        # Duration
        if self._play_start_time:
            elapsed = datetime.now(tz=timezone.utc) - self._play_start_time
            secs = int(elapsed.total_seconds())
            if secs >= 60:
                mins, secs_rem = divmod(secs, 60)
                self._print(f"  [dim]Duration: {mins}m {secs_rem}s[/dim]")
            else:
                self._print(f"  [dim]Duration: {secs}s[/dim]")

    # ── Misc Events ──────────────────────────────────────────────

    def v2_playbook_on_no_hosts_matched(self):
        self._print("[failed]  No hosts matched[/failed]")

    def v2_playbook_on_no_hosts_remaining(self):
        self._print("[failed]  No more hosts remaining[/failed]")

    def v2_runner_retry(self, result):
        attempts = result._result.get("attempts", 0)
        retries = result._result.get("retries", 0)
        msg = result._result.get("msg", "")
        name = self._task_name or result._task.get_name().strip()
        self._print(
            f"  [changed]{SYM_CHANGED}[/changed] [task_name]{escape(name)}[/task_name] "
            f"[detail]retry {attempts}/{retries}"
            + (f" - {escape(msg)}" if msg else "")
            + "[/detail]"
        )

    def v2_playbook_on_include(self, included_file):
        # Suppress — include paths are noise; the included tasks show individually
        pass
