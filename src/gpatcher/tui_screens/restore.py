import os
import contextlib
from textual.app import ComposeResult
from textual.widgets import Label, Input, Switch, Button, RichLog
from textual.containers import Horizontal
from textual.worker import Worker, WorkerState

from gpatcher.core.restore import invoke_restore
from gpatcher.tui_screens.base import BaseFormScreen, TextualLogRedirector

class RestoreBackupScreen(BaseFormScreen):
    title_text = "Restore Patch Backup"
    submit_label = "Start Restore"

    def compose_form(self) -> ComposeResult:
        yield Label("Target Game Directory:")
        yield Input(placeholder="e.g. D:/Games/Hades", id="target-input")
        yield Label("Backup Folder Name (default: 'latest'):")
        yield Input(value="latest", placeholder="e.g. latest", id="backup-input")
        with Horizontal(classes="form-row"):
            yield Label("Keep backup folder after restore completes?")
            yield Switch(value=False, id="keep-backup-switch")

    def submit_form(self) -> None:
        target = self.query_one("#target-input", Input).value.strip().strip('"').strip("'")
        backup = self.query_one("#backup-input", Input).value.strip()
        keep_backup = self.query_one("#keep-backup-switch", Switch).value

        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)

        if not target or not os.path.isdir(target):
            log_widget.write(f"[err] Target game directory does not exist: {target}\n")
            return

        target_abs = os.path.abspath(os.path.expanduser(target))

        self.query_one("#btn-submit", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True
        log_widget.write("Starting backup restoration worker thread...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                invoke_restore(target_abs, backup=backup, keep_backup=keep_backup)

        def on_complete(worker: Worker):
            self.query_one("#btn-submit", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                log_widget.write("[ok] Restore complete!\n")
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Error: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))
