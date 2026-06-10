import contextlib
from textual.app import ComposeResult
from textual.widgets import Label, Switch, Button, RichLog
from textual.containers import Horizontal
from textual.worker import Worker, WorkerState

from gpatcher.core.update import invoke_update
from gpatcher.tui_screens.base import BaseFormScreen, TextualLogRedirector

class UpdateScreen(BaseFormScreen):
    title_text = "Update GPatcher"
    submit_label = "Check & Install Updates"

    def compose_form(self) -> ComposeResult:
        with Horizontal(classes="form-row"):
            yield Label("Force re-install of the latest version even if up-to-date?")
            yield Switch(value=False, id="force-switch")

    def submit_form(self) -> None:
        force = self.query_one("#force-switch", Switch).value
        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)

        self.query_one("#btn-submit", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True
        log_widget.write("Checking for updates from GitHub releases...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                invoke_update(force=force)

        def on_complete(worker: Worker):
            self.query_one("#btn-submit", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                log_widget.write("[ok] Update process completed!\n")
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Update failed: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))
