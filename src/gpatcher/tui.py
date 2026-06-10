from textual.app import App, ComposeResult
from textual.screen import Screen
from textual.widgets import Footer, OptionList, Static
from textual.containers import Vertical, Horizontal

from gpatcher.tui_screens.base import LOGO_TEXT, get_doctor_status
from gpatcher.tui_screens import (
    ApplyPatchScreen,
    CreatePatchScreen,
    RestoreBackupScreen,
    SearchFetchScreen,
    UploadPatchScreen,
    VerifyInstallScreen,
    DoctorDiagnosticsScreen,
    UpdateScreen
)

class MainDashboardScreen(Screen):
    """The main menu dashboard showing the logo, system status, and operations list."""
    
    def compose(self) -> ComposeResult:
        yield Static(LOGO_TEXT, id="logo-header")
        
        status = get_doctor_status()
        dt_str = "detools: [OK]" if status['detools'] else "detools: [ERR]"
        py_str = f"python: [{status['python']}]" if isinstance(status['python'], str) else "python: [OK]"
        ia_str = "internetarchive: [OK]" if status['ia'] else "internetarchive: [WARN]"

        dt_class = "ok-status" if status['detools'] else "err-status"
        ia_class = "ok-status" if status['ia'] else "err-status"
        
        yield Horizontal(
            Static(dt_str, classes=f"status-indicator {dt_class}"),
            Static(ia_str, classes=f"status-indicator {ia_class}"),
            Static(py_str, classes="status-indicator ok-status"),
            id="status-bar"
        )
        
        with Horizontal(id="dashboard-body"):
            yield OptionList(
                "Apply a game patch",
                "Create a game patch",
                "Restore from a backup",
                "Search & Fetch patch from Internet Archive",
                "Upload patch to Internet Archive",
                "Verify an installation",
                "System diagnostics check (doctor)",
                "Check / Install gpatcher updates",
                "Exit",
                id="menu-list"
            )
            with Vertical(id="details-panel"):
                yield Static("GPatcher Interactive Menu", classes="panel-title")
                yield Static(
                    "Welcome to the GPatcher Dashboard! Select an operation from the menu to get started.",
                    id="details-text"
                )
        yield Footer()

    def on_option_list_option_highlighted(self, event: OptionList.OptionHighlighted) -> None:
        descriptions = [
            "Apply a patch ZIP package or URL to a target installation directory. Validates old files and supports rollback backups.",
            "Compute binary delta patches (.hdiff) between old and new directories and package them into a release ZIP bundle.",
            "Undo a previously applied patch by restoring stashed backup files and cleaning up added files.",
            "Search Internet Archive (archive.org) for game patches and download them directly.",
            "Publish a generated patch ZIP package to the Internet Archive with metadata description and creator fields.",
            "Scan an installation folder against a manifest snapshot or ZIP patch to find missing or tampered files.",
            "Perform dependency audits, checking if Python packages (detools, internetarchive) are correctly installed.",
            "Check for newer releases of GPatcher on GitHub and install updates automatically.",
            "Close the interactive GPatcher dashboard."
        ]
        text_widget = self.query_one("#details-text", Static)
        if event.option_index is not None and 0 <= event.option_index < len(descriptions):
            text_widget.update(descriptions[event.option_index])

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        idx = event.option_index
        if idx == 0:
            self.app.push_screen(ApplyPatchScreen())
        elif idx == 1:
            self.app.push_screen(CreatePatchScreen())
        elif idx == 2:
            self.app.push_screen(RestoreBackupScreen())
        elif idx == 3:
            self.app.push_screen(SearchFetchScreen())
        elif idx == 4:
            self.app.push_screen(UploadPatchScreen())
        elif idx == 5:
            self.app.push_screen(VerifyInstallScreen())
        elif idx == 6:
            self.app.push_screen(DoctorDiagnosticsScreen())
        elif idx == 7:
            self.app.push_screen(UpdateScreen())
        elif idx == 8:
            self.app.exit()

class GPatcherApp(App):
    CSS_PATH = "gpatcher.tcss"
    TITLE = "GPatcher Delta Patching Dashboard"
    
    def on_mount(self) -> None:
        self.push_screen(MainDashboardScreen())

def invoke_interactive_menu():
    app = GPatcherApp()
    app.run()

def main():
    invoke_interactive_menu()

if __name__ == '__main__':
    main()
