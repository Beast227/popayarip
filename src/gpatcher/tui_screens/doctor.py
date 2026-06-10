import contextlib
from textual.app import ComposeResult
from textual.widgets import Label, Button, RichLog
from textual.worker import Worker, WorkerState

from gpatcher.core.doctor import invoke_doctor
from gpatcher.tui_screens.base import BaseFormScreen, TextualLogRedirector

class DoctorDiagnosticsScreen(BaseFormScreen):
    title_text = "System Diagnostics"
    submit_label = "Run Diagnostics"

    def compose_form(self) -> ComposeResult:
        yield Label("Environment & Dependency Verification Status:")

    def submit_form(self) -> None:
        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)

        self.query_one("#btn-submit", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True
        log_widget.write("Running doctor diagnostic checks...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                invoke_doctor()

        def on_complete(worker: Worker):
            self.query_one("#btn-submit", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Diagnostics execution failed: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))
