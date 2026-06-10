import os
import sys
import re
import io
import contextlib

from textual.app import ComposeResult
from textual.screen import Screen
from textual.widgets import Label, RichLog, Button, Static
from textual.containers import Vertical, Horizontal
from textual.worker import Worker, WorkerState

from gpatcher.core.common import GPATCHER_VERSION

LOGO_TEXT = f"""
   ____ ____   _  _____ ____ _   _ _____ ____           
  / ___|  _ \\ / \\|_   _/ ___| | | | ____|  _ \\          
 | |  _| |_) / _ \\ | | | |   | |_| |  _| | |_) |        
 | |_| |  __/ ___ \\| | | |___|  _  | |___|  _ <         
  \\____|_| /_/   \\_\\_|  \\____|_| |_|_____|_| \\_\\  v{GPATCHER_VERSION}

            Game Delta Patching Dashboard
"""

def get_doctor_status() -> dict:
    python = True
    try:
        import detools
        dt = True
    except ImportError:
        dt = False
    try:
        import internetarchive
        ia = True
    except ImportError:
        ia = False
    return {
        'detools': dt,
        'python': python,
        'ia': ia
    }

class TextualLogRedirector:
    """Redirects stdout to a RichLog widget. 
    Intercepts progress updates (with carriage return '\\r') and routes them to a dedicated status Label.
    """
    def __init__(self, log_widget: RichLog, status_label: Label = None):
        self.log_widget = log_widget
        self.status_label = status_label

    def write(self, text: str):
        # Remove ANSI color sequences
        clean_text = re.sub(r'\033\[[0-9;]*m', '', text)
        if not clean_text:
            return
        
        # Capture progress indicator strings (containing \\r)
        if '\r' in clean_text:
            parts = clean_text.split('\r')
            progress_msg = parts[-1].strip()
            if progress_msg and self.status_label:
                self.log_widget.app.call_from_thread(self.status_label.update, progress_msg)
            return

        # Write normal log lines
        lines = clean_text.split('\n')
        for line in lines:
            line_str = line.strip()
            if line_str:
                self.log_widget.app.call_from_thread(self.log_widget.write, line_str)

    def flush(self):
        pass

class BaseFormScreen(Screen):
    """Base Screen containing consistent layouts with forms, submit buttons, status labels and logs."""
    title_text = ""
    submit_label = "Submit"

    BINDINGS = [("escape", "back", "Back to Menu")]

    def action_back(self) -> None:
        self.app.pop_screen()

    def compose(self) -> ComposeResult:
        with Vertical(classes="form-container"):
            yield Static(self.title_text, classes="form-title")
            yield from self.compose_form()
            yield Label("", id="status-label")
            yield RichLog(id="console-log", max_lines=1000)
            with Horizontal(classes="form-buttons"):
                yield Button(self.submit_label, variant="success", id="btn-submit")
                yield Button("Back to Menu", variant="error", id="btn-cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-cancel":
            self.app.pop_screen()
        elif event.button.id == "btn-submit":
            self.submit_form()

    def handle_worker_status(self, event: Worker.StateChanged, on_complete_cb) -> None:
        if event.state in (WorkerState.SUCCESS, WorkerState.ERROR):
            on_complete_cb(event.worker)
