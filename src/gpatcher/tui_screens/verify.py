import os
import contextlib
from textual.app import ComposeResult
from textual.widgets import Label, Input, Button, RichLog
from textual.worker import Worker, WorkerState

from gpatcher.core.verify import invoke_verify
from gpatcher.tui_screens.base import BaseFormScreen, TextualLogRedirector

class VerifyInstallScreen(BaseFormScreen):
    title_text = "Verify Installation"
    submit_label = "Verify"

    def compose_form(self) -> ComposeResult:
        yield Label("Installation Directory to Verify:")
        yield Input(placeholder="e.g. D:/Games/Hades", id="install-input")
        yield Label("Reference manifest.json or patch ZIP path:")
        yield Input(placeholder="e.g. D:/patches/hades_v1.0-to-v1.2.patch.zip or manifest.json", id="against-input")

    def submit_form(self) -> None:
        install = self.query_one("#install-input", Input).value.strip().strip('"').strip("'")
        against = self.query_one("#against-input", Input).value.strip().strip('"').strip("'")

        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)

        if not install or not os.path.isdir(install):
            log_widget.write(f"[err] Installation folder does not exist: {install}\n")
            return
        if not against or not os.path.exists(against):
            log_widget.write(f"[err] Reference manifest/zip path does not exist: {against}\n")
            return

        install_abs = os.path.abspath(os.path.expanduser(install))
        against_abs = os.path.abspath(os.path.expanduser(against))

        self.query_one("#btn-submit", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True
        log_widget.write("Starting verification worker thread...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                invoke_verify(install_abs, against_abs)

        def on_complete(worker: Worker):
            self.query_one("#btn-submit", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                log_widget.write("[ok] Verification completed! Integrity matches standard snapshot.\n")
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Verification failed: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))
