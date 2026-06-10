import os
import contextlib
from textual.app import ComposeResult
from textual.widgets import Label, Input, Switch, Button, RichLog
from textual.containers import Horizontal
from textual.worker import Worker, WorkerState

from gpatcher.core.apply import invoke_apply
from gpatcher.tui_screens.base import BaseFormScreen, TextualLogRedirector

class ApplyPatchScreen(BaseFormScreen):
    title_text = "Apply Game Patch"
    submit_label = "Start Applying"

    def compose_form(self) -> ComposeResult:
        yield Label("Patch ZIP File Path or URL:")
        yield Input(placeholder="e.g. C:/patches/game.patch.zip or https://site.com/patch.zip", id="patch-input")
        yield Label("Target Game Installation Directory:")
        yield Input(placeholder="e.g. D:/Games/Hades", id="target-input")
        with Horizontal(classes="form-row"):
            yield Label("Dry Run (verification only)?")
            yield Switch(value=False, id="dry-run-switch")
        with Horizontal(classes="form-row"):
            yield Label("Disable Backup generation?")
            yield Switch(value=False, id="no-backup-switch")
        with Horizontal(classes="form-row"):
            yield Label("Keep Backup folder after successful apply?")
            yield Switch(value=True, id="keep-backup-switch")

    def submit_form(self) -> None:
        patch_path = self.query_one("#patch-input", Input).value.strip()
        target = self.query_one("#target-input", Input).value.strip()
        dry_run = self.query_one("#dry-run-switch", Switch).value
        no_backup = self.query_one("#no-backup-switch", Switch).value
        keep_backup = self.query_one("#keep-backup-switch", Switch).value

        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)
        
        if not patch_path:
            log_widget.write("[err] Patch path cannot be empty!\n")
            return
        if not target:
            log_widget.write("[err] Target directory cannot be empty!\n")
            return
        
        patch_path = patch_path.strip('"').strip("'")
        target = target.strip('"').strip("'")
        target_abs = os.path.abspath(os.path.expanduser(target))

        if not patch_path.startswith(('http://', 'https://')) and not os.path.exists(patch_path):
            log_widget.write(f"[err] Local patch path does not exist: {patch_path}\n")
            return
        if not os.path.isdir(target_abs):
            log_widget.write(f"[err] Target directory does not exist or is not a folder: {target_abs}\n")
            return

        self.query_one("#btn-submit", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True
        log_widget.write("Starting patch application worker thread...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                invoke_apply(patch_path, target_abs, dry_run=dry_run, no_backup=no_backup, keep_backup=keep_backup)

        def on_complete(worker: Worker):
            self.query_one("#btn-submit", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                log_widget.write("[ok] Patch operation completed successfully!\n")
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Error: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))
