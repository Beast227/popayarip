import os
import re
import io
import contextlib
from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Label, Input, Button, OptionList, Static, RichLog
from textual.worker import Worker, WorkerState

from gpatcher.ia.client import invoke_search, invoke_fetch
from gpatcher.tui_screens.base import LOGO_TEXT, TextualLogRedirector

class SearchFetchScreen(Screen):
    BINDINGS = [("escape", "back", "Back to Menu")]

    def action_back(self) -> None:
        self.app.pop_screen()

    def compose(self) -> ComposeResult:
        with Vertical(classes="form-container"):
            yield Static("Search & Fetch Patches (Internet Archive)", classes="form-title")
            
            yield Label("Game Title to Search:")
            with Horizontal(classes="form-row"):
                yield Input(placeholder="e.g. Hades", id="query-input")
                yield Button("Search", variant="primary", id="btn-search")
                
            yield Label("Select Patch to Fetch:")
            yield OptionList(id="results-list")
            
            yield Label("Output Folder:")
            yield Input(value=".", placeholder="e.g. .", id="out-dir-input")
            
            yield Label("", id="status-label")
            yield RichLog(id="console-log", max_lines=1000)
            
            with Horizontal(classes="form-buttons"):
                yield Button("Fetch Selected Patch", variant="success", id="btn-fetch", disabled=True)
                yield Button("Back to Menu", variant="error", id="btn-cancel")

    def on_mount(self) -> None:
        self.search_identifiers = []

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-cancel":
            self.app.pop_screen()
        elif event.button.id == "btn-search":
            self.run_search()
        elif event.button.id == "btn-fetch":
            self.run_fetch()

    def run_search(self) -> None:
        query = self.query_one("#query-input", Input).value.strip()
        log_widget = self.query_one("#console-log", RichLog)
        opt_list = self.query_one("#results-list", OptionList)
        status_label = self.query_one("#status-label", Label)
        
        if not query:
            log_widget.write("[err] Search query cannot be empty!\n")
            return

        self.query_one("#btn-search", Button).disabled = True
        self.query_one("#btn-fetch", Button).disabled = True
        opt_list.clear()
        self.search_identifiers = []

        log_widget.write(f"Searching archive.org for '{query}'...\n")

        def bg_task():
            f = io.StringIO()
            with contextlib.redirect_stdout(f):
                invoke_search(query)
            return f.getvalue()

        def on_complete(worker: Worker):
            self.query_one("#btn-search", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                res = worker.result
                lines = [l.strip() for l in res.splitlines() if l.startswith("Found: ")]
                if not lines:
                    log_widget.write(f"[warn] No patches found for query '{query}'.\n")
                    opt_list.add_option("No patches found.")
                else:
                    for line in lines:
                        match = re.match(r'Found: (\S+)\s*-\s*(.*)', line)
                        if match:
                            ident = match.group(1)
                            title = match.group(2)
                            self.search_identifiers.append(ident)
                            opt_list.add_option(f"{ident} - {title}")
                        else:
                            match_simple = re.match(r'Found: (\S+)', line)
                            if match_simple:
                                ident = match_simple.group(1)
                                self.search_identifiers.append(ident)
                                opt_list.add_option(ident)
                    self.query_one("#btn-fetch", Button).disabled = False
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Search failed: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))

    def run_fetch(self) -> None:
        opt_list = self.query_one("#results-list", OptionList)
        idx = opt_list.highlighted
        if idx is None or idx < 0 or idx >= len(self.search_identifiers):
            return

        selected_id = self.search_identifiers[idx]
        out_dir = self.query_one("#out-dir-input", Input).value.strip().strip('"').strip("'")
        
        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)

        match_slug = re.match(r'(?:gpatcher|popayarip)-([a-zA-Z0-9\-]+)-([a-zA-Z0-9\.\-]+)-to-([a-zA-Z0-9\.\-]+)', selected_id)
        if not match_slug:
            log_widget.write(f"[err] Invalid patch identifier format: {selected_id}\n")
            return

        slug = match_slug.group(1)
        from_v = match_slug.group(2)
        to_v = match_slug.group(3)
        out_dir_abs = os.path.abspath(os.path.expanduser(out_dir))

        self.query_one("#btn-search", Button).disabled = True
        self.query_one("#btn-fetch", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True

        log_widget.write(f"Fetching selected patch {selected_id} to {out_dir_abs}...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                invoke_fetch(slug, from_v, to_v, out_dir=out_dir_abs)

        def on_complete(worker: Worker):
            self.query_one("#btn-search", Button).disabled = False
            self.query_one("#btn-fetch", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                log_widget.write("[ok] Download complete!\n")
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Error downloading: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))

    def handle_worker_status(self, event: Worker.StateChanged, on_complete_cb) -> None:
        if event.state in (WorkerState.SUCCESS, WorkerState.ERROR):
            on_complete_cb(event.worker)

# Import dependencies inside containers to avoid circular imports during loading
from textual.containers import Vertical, Horizontal
