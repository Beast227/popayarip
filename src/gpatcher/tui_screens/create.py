import os
import re
import contextlib
from textual.app import ComposeResult
from textual.widgets import Label, Input, Button, RichLog
from textual.worker import Worker, WorkerState

from gpatcher.core.create import invoke_create
from gpatcher.tui_screens.base import BaseFormScreen, TextualLogRedirector

class CreatePatchScreen(BaseFormScreen):
    title_text = "Create Game Patch"
    submit_label = "Start Creating"

    def compose_form(self) -> ComposeResult:
        yield Label("Game Title:")
        yield Input(placeholder="e.g. Hades", id="game-input")
        yield Label("Old Game Version Directory:")
        yield Input(placeholder="e.g. D:/Games/Hades_v1.0", id="old-dir-input")
        yield Label("New Game Version Directory:")
        yield Input(placeholder="e.g. D:/Games/Hades_v1.2", id="new-dir-input")
        yield Label("Old Version Label (Optional - Auto-detected if empty):")
        yield Input(placeholder="e.g. 1.0", id="old-ver-input")
        yield Label("New Version Label (Optional - Auto-detected if empty):")
        yield Input(placeholder="e.g. 1.2", id="new-ver-input")
        yield Label("Output Folder:")
        yield Input(value=".", placeholder="e.g. .", id="out-dir-input")
        yield Label("Custom Exclude Patterns (Optional - Comma separated):")
        yield Input(placeholder="e.g. Mods/*, *.bak", id="exclude-input")

    def submit_form(self) -> None:
        game = self.query_one("#game-input", Input).value.strip()
        old_dir = self.query_one("#old-dir-input", Input).value.strip().strip('"').strip("'")
        new_dir = self.query_one("#new-dir-input", Input).value.strip().strip('"').strip("'")
        old_ver = self.query_one("#old-ver-input", Input).value.strip()
        new_ver = self.query_one("#new-ver-input", Input).value.strip()
        out_dir = self.query_one("#out-dir-input", Input).value.strip().strip('"').strip("'")
        custom_ex = self.query_one("#exclude-input", Input).value.strip()

        log_widget = self.query_one("#console-log", RichLog)
        status_label = self.query_one("#status-label", Label)

        if not game:
            log_widget.write("[err] Game title cannot be empty!\n")
            return
        if not old_dir or not os.path.isdir(old_dir):
            log_widget.write(f"[err] Old directory does not exist: {old_dir}\n")
            return
        if not new_dir or not os.path.isdir(new_dir):
            log_widget.write(f"[err] New directory does not exist: {new_dir}\n")
            return

        excludes = []
        if custom_ex:
            excludes = [x.strip() for x in re.split(r'[,;]', custom_ex) if x.strip()]

        old_dir_abs = os.path.abspath(os.path.expanduser(old_dir))
        new_dir_abs = os.path.abspath(os.path.expanduser(new_dir))
        out_dir_abs = os.path.abspath(os.path.expanduser(out_dir))

        self.query_one("#btn-submit", Button).disabled = True
        self.query_one("#btn-cancel", Button).disabled = True
        log_widget.write("Starting patch creation worker thread...\n")

        def bg_task():
            redirector = TextualLogRedirector(log_widget, status_label)
            with contextlib.redirect_stdout(redirector):
                bundle = invoke_create(old_dir_abs, new_dir_abs, game, old_ver or None, new_ver or None, out_dir=out_dir_abs, exclude=excludes)
                print(f"[ok] Patch bundle created: {bundle}")

        def on_complete(worker: Worker):
            self.query_one("#btn-submit", Button).disabled = False
            self.query_one("#btn-cancel", Button).disabled = False
            status_label.update("")
            if worker.state == WorkerState.SUCCESS:
                log_widget.write("[ok] Patch creation complete!\n")
            elif worker.state == WorkerState.ERROR:
                log_widget.write(f"[err] Error: {worker.error}\n")

        self.run_worker(bg_task, thread=True, on_status_change=lambda e: self.handle_worker_status(e, on_complete))
