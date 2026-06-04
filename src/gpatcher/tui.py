import sys
import os
import shutil
import time
import re
from gpatcher.core.common import GPATCHER_VERSION, Colors, get_bin_path, get_app_data_dir, log_info, log_ok, log_warn, log_err
from gpatcher.core.apply import invoke_apply
from gpatcher.core.create import invoke_create
from gpatcher.core.restore import invoke_restore
from gpatcher.core.verify import invoke_verify
from gpatcher.core.doctor import invoke_doctor
from gpatcher.ia.client import invoke_search, invoke_fetch

def get_key() -> str:
    """Reads a single keypress without echoing to the console.
    Returns standard key names like 'up', 'down', 'enter', 'escape', or character strings.
    """
    if sys.platform == 'win32':
        import msvcrt
        ch = msvcrt.getch()
        if ch in (b'\x00', b'\xe0'):
            ch2 = msvcrt.getch()
            if ch2 == b'H': return 'up'
            if ch2 == b'P': return 'down'
            return None
        if ch == b'\r': return 'enter'
        if ch == b'\x1b': return 'escape'
        try:
            return ch.decode('utf-8', errors='ignore')
        except Exception:
            return None
    else:
        import tty
        import termios
        import select
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(sys.stdin.fileno())
            ch = sys.stdin.read(1)
            if ch == '\x1b':
                r, _, _ = select.select([sys.stdin], [], [], 0.05)
                if r:
                    ch2 = sys.stdin.read(2)
                    if ch2 == '[A': return 'up'
                    if ch2 == '[B': return 'down'
                else:
                    return 'escape'
            elif ch in ('\r', '\n'):
                return 'enter'
            elif ch in ('\x7f', '\x08'):
                return 'backspace'
            return ch
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def hide_cursor():
    sys.stdout.write("\033[?25l")
    sys.stdout.flush()

def show_cursor():
    sys.stdout.write("\033[?25h")
    sys.stdout.flush()

def move_cursor_top_left():
    sys.stdout.write("\033[H")
    sys.stdout.flush()

def clear_screen():
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()

def get_layout_width() -> int:
    try:
        w = os.get_terminal_size().columns - 6
        if w < 56: w = 56
        if w > 80: w = 80
        return w
    except Exception:
        return 56

def get_centered_line(text: str, width: int) -> str:
    pad_total = width - len(text)
    if pad_total <= 0:
        return text[:width]
    pad_left = pad_total // 2
    pad_right = pad_total - pad_left
    return (" " * pad_left) + text + (" " * pad_right)

def get_padded_line(text: str, width: int) -> str:
    if len(text) >= width:
        return text[:width]
    return text + (" " * (width - len(text)))

def draw_box_top(title: str):
    w = get_layout_width()
    line = f"-- {title} "
    if len(line) > w:
        line = line[:w]
    else:
        line = line + ("-" * (w - len(line)))
    print(f"  {Colors.CYAN}+{line}+{Colors.RESET}")

def draw_box_bottom():
    w = get_layout_width()
    print(f"  {Colors.CYAN}+{'-' * w}+{Colors.RESET}")

def get_doctor_status() -> dict:
    is_win = sys.platform == 'win32'
    bin_ext = '.exe' if is_win else ''
    hdiffz = os.path.exists(get_bin_path(f"hdiffz{bin_ext}"))
    hpatchz = os.path.exists(get_bin_path(f"hpatchz{bin_ext}"))
    python = True
    try:
        import internetarchive
        ia = True
    except ImportError:
        ia = False
    return {
        'hdiffz': hdiffz,
        'hpatchz': hpatchz,
        'python': python,
        'ia': ia
    }

def draw_header():
    w = get_layout_width()
    border = "+" + ("-" * w) + "+"
    print(f"  {Colors.MAGENTA}{border}{Colors.RESET}")

    logo_lines = [
        "   ____ ____   _  _____ ____ _   _ _____ ____           ",
        "  / ___|  _ \\ / \\|_   _/ ___| | | | ____|  _ \\          ",
        " | |  _| |_) / _ \\ | | | |   | |_| |  _| | |_) |        ",
        " | |_| |  __/ ___ \\| | | |___|  _  | |___|  _ <         ",
        f"  \\____|_| /_/   \\_\\_|  \\____|_| |_|_____|_| \\_\\  v{GPATCHER_VERSION}  ",
        "",
        "            Game Delta Patching Dashboard               "
    ]

    for line in logo_lines:
        centered = get_centered_line(line, w)
        sys.stdout.write(f"  {Colors.MAGENTA}|")
        if line == logo_lines[-1]:
            sys.stdout.write(f"{Colors.GRAY}{centered}")
        else:
            sys.stdout.write(f"{Colors.MAGENTA}{centered}")
        sys.stdout.write(f"|{Colors.RESET}\n")

    print(f"  {Colors.MAGENTA}{border}{Colors.RESET}")

    status = get_doctor_status()
    hdiffz_str = "[OK] hdiffz" if status['hdiffz'] else "[ERR] hdiffz"
    hpatchz_str = "[OK] hpatchz" if status['hpatchz'] else "[ERR] hpatchz"
    python_str = "[OK] python" if status['python'] else "[ERR] python"

    hdiffz_col = Colors.GREEN if status['hdiffz'] else Colors.RED
    hpatchz_col = Colors.GREEN if status['hpatchz'] else Colors.RED
    python_col = Colors.GREEN

    sys.stdout.write(f"  {Colors.GRAY}[ Status ]  ")
    sys.stdout.write(f"{hdiffz_col}{hdiffz_str}  {Colors.GRAY}|  ")
    sys.stdout.write(f"{hpatchz_col}{hpatchz_str}  {Colors.GRAY}|  ")
    sys.stdout.write(f"{python_col}{python_str}\n{Colors.RESET}\n")
    sys.stdout.flush()

def read_menu_selection(title: str, options: list) -> int:
    """Renders an interactive selection box using in-place cursor positioning."""
    interactive = True
    try:
        # Check standard input stream capability
        if not sys.stdin.isatty():
            interactive = False
    except Exception:
        interactive = False

    if interactive:
        selected_index = 0
        running = True
        try:
            hide_cursor()
            clear_screen()
        except Exception:
            pass

        last_selected_index = -1
        last_width = -1

        while running:
            w = get_layout_width()
            if selected_index != last_selected_index or w != last_width:
                if w != last_width:
                    try: clear_screen()
                    except Exception: pass
                else:
                    try: move_cursor_top_left()
                    except Exception: pass

                draw_header()
                draw_box_top(title)
                
                for i, opt in enumerate(options):
                    if i == selected_index:
                        opt_text = f"  >  [ {opt} ]"
                        padded = get_padded_line(opt_text, w)
                        sys.stdout.write(f"  {Colors.CYAN}|{Colors.BG_MAGENTA}{Colors.WHITE}{padded}{Colors.RESET}{Colors.CYAN}|{Colors.RESET}\n")
                    else:
                        opt_text = f"     [ {opt} ]"
                        padded = get_padded_line(opt_text, w)
                        sys.stdout.write(f"  {Colors.CYAN}|{Colors.GRAY}{padded}{Colors.CYAN}|{Colors.RESET}\n")
                
                draw_box_bottom()
                last_selected_index = selected_index
                last_width = w

            key = get_key()
            if key == 'up':
                selected_index = (selected_index - 1 + len(options)) % len(options)
            elif key == 'down':
                selected_index = (selected_index + 1) % len(options)
            elif key == 'enter':
                running = False
            elif key == 'escape':
                selected_index = -1
                running = False

        try:
            show_cursor()
        except Exception:
            pass

        if interactive:
            return selected_index

    # Non-interactive fallback
    w = get_layout_width()
    try: clear_screen()
    except Exception: pass
    draw_header()
    draw_box_top(title)
    for i, opt in enumerate(options):
        opt_text = f"   {i + 1}) {opt}"
        padded = get_padded_line(opt_text, w)
        print(f"  {Colors.CYAN}|{padded}|{Colors.RESET}")
    draw_box_bottom()
    print()

    valid = False
    choice = 0
    while not valid:
        sys.stdout.write(f"  {Colors.CYAN}> Enter option (1-{len(options)}) or 'q' to go back: {Colors.RESET}")
        sys.stdout.flush()
        val = sys.stdin.readline().strip()
        if val.lower() == 'q':
            return -1
        if val.isdigit():
            num = int(val)
            if 1 <= num <= len(options):
                choice = num - 1
                valid = True
        if not valid:
            print(f"  {Colors.RED}[err] Invalid selection!{Colors.RESET}")
    return choice

def read_custom_input(prompt: str, default: str = "") -> str:
    """Reads character-by-character to allow canceling via Escape key."""
    display = f"  | > {prompt} [{default}]: " if default else f"  | > {prompt}: "
    sys.stdout.write(f"{Colors.CYAN}{display}{Colors.RESET}")
    sys.stdout.flush()

    interactive = True
    try:
        if not sys.stdin.isatty():
            interactive = False
    except Exception:
        interactive = False

    if not interactive:
        val = sys.stdin.readline().strip()
        if not val:
            val = default
        if val.lower() in ('q', 'back'):
            return None
        return val

    input_str = ""
    try: show_cursor()
    except Exception: pass

    while True:
        key = get_key()
        if key == 'enter':
            print()
            if not input_str and default:
                return default
            return input_str
        elif key == 'escape':
            print(f" {Colors.YELLOW}(cancelled){Colors.RESET}")
            return None
        elif key in ('up', 'down'):
            continue
        elif key in ('backspace', '\x7f', '\x08'):
            if len(input_str) > 0:
                input_str = input_str[:-1]
                sys.stdout.write("\b \b")
                sys.stdout.flush()
        elif key and len(key) == 1 and 32 <= ord(key) <= 126:
            input_str += key
            sys.stdout.write(key)
            sys.stdout.flush()

def read_text_input(prompt: str, default: str = "") -> str:
    return read_custom_input(prompt, default)

def read_path_input(prompt: str, must_exist: bool = False, is_directory: bool = False) -> str:
    valid = False
    resolved = ""
    while not valid:
        val = read_custom_input(prompt)
        if val is None:
            return None
        if not val:
            print(f"  |   {Colors.RED}[err] Path cannot be empty!{Colors.RESET}")
            continue
        resolved = os.path.abspath(os.path.expanduser(val))
        if must_exist:
            if not os.path.exists(resolved):
                print(f"  |   {Colors.RED}[err] Path does not exist: {resolved}{Colors.RESET}")
                continue
            if is_directory and not os.path.isdir(resolved):
                print(f"  |   {Colors.RED}[err] Path is not a directory!{Colors.RESET}")
                continue
        valid = True
    return resolved

def read_confirm_choice(prompt: str, default: bool = True) -> bool:
    opt = "(Y/n)" if default else "(y/N)"
    choice = read_menu_selection(f"{prompt} {opt}", ["Yes", "No"])
    if choice == -1:
        return None
    return choice == 0

def invoke_interactive_menu():
    """Launches the main interactive dashboard loop."""
    menu_options = [
        "Apply a game patch",
        "Create a game patch",
        "Restore from a backup",
        "Search & Fetch patch from Internet Archive",
        "Verify an installation",
        "System diagnostics check (doctor)",
        "Check / Fetch tools (fetch)",
        "Check / Install gpatcher updates (update)",
        "Exit"
    ]

    running = True
    while running:
        selection = read_menu_selection("Select Operation", menu_options)
        if selection == -1 or selection == 8:
            running = False
            print(f"  {Colors.GREEN}> Goodbye!{Colors.RESET}")
            break

        try: clear_screen()
        except Exception: pass
        draw_header()
        print()

        if selection == 0:  # Apply Patch
            draw_box_top("Apply Game Patch")
            patch = read_text_input("Enter local patch ZIP path or URL")
            if patch is None: continue
            target = read_path_input("Enter target game directory", must_exist=True, is_directory=True)
            if target is None: continue
            draw_box_bottom()

            dry_run = read_confirm_choice("Run as Dry Run (no file changes)?", default=False)
            if dry_run is None: continue
            no_backup = read_confirm_choice("Disable backup generation?", default=False)
            if no_backup is None: continue
            keep_backup = read_confirm_choice("Keep backup directory after successful apply?", default=True)
            if keep_backup is None: continue

            print(f"\n  {Colors.YELLOW}> Running apply operation...{Colors.RESET}")
            try:
                invoke_apply(patch, target, dry_run=dry_run, no_backup=no_backup, keep_backup=keep_backup)
            except Exception as e:
                log_err(f"Apply failed: {e}")

        elif selection == 1:  # Create Patch
            draw_box_top("Create Game Patch")
            game = read_text_input("Enter game title (e.g. Hades)")
            if game is None: continue
            old_dir = read_path_input("Enter old game directory", must_exist=True, is_directory=True)
            if old_dir is None: continue
            new_dir = read_path_input("Enter new game directory", must_exist=True, is_directory=True)
            if new_dir is None: continue

            # Auto-detect versions
            from gpatcher.core.version_detect import detect_version
            detected_old = detect_version(old_dir) or ""
            detected_new = detect_version(new_dir) or ""

            old_ver = read_text_input("Enter old version", default=detected_old)
            if old_ver is None: continue
            new_ver = read_text_input("Enter new version", default=detected_new)
            if new_ver is None: continue
            out_dir = read_text_input("Enter output folder", default=".")
            if out_dir is None: continue
            custom_ex = read_text_input("Custom excludes (e.g. Mods/*,*.bak) [Optional]")
            if custom_ex is None: continue
            draw_box_bottom()

            excludes = []
            if custom_ex:
                excludes = [x.strip() for x in re.split(r'[,;]', custom_ex)]

            print(f"\n  {Colors.YELLOW}> Running patch creation...{Colors.RESET}")
            try:
                bundle = invoke_create(old_dir, new_dir, game, old_ver, new_ver, out_dir=out_dir, exclude=excludes)
                log_ok(f"Patch bundle created: {bundle}")
            except Exception as e:
                log_err(f"Create failed: {e}")

        elif selection == 2:  # Restore Backup
            draw_box_top("Restore Patch Backup")
            target = read_path_input("Enter target game directory", must_exist=True, is_directory=True)
            if target is None: continue
            backup = read_text_input("Enter backup folder name", default="latest")
            if backup is None: continue
            draw_box_bottom()

            keep_backup = read_confirm_choice("Keep backup folder after restore completes?", default=False)
            if keep_backup is None: continue

            print(f"\n  {Colors.YELLOW}> Restoring backup...{Colors.RESET}")
            try:
                invoke_restore(target, backup=backup, keep_backup=keep_backup)
            except Exception as e:
                log_err(f"Restore failed: {e}")

        elif selection == 3:  # Search & Fetch
            draw_box_top("Search Internet Archive")
            query = read_text_input("Enter game title to search")
            if query is None: continue
            draw_box_bottom()

            print(f"\n  {Colors.YELLOW}> Searching...{Colors.RESET}")
            try:
                # Capture search prints internally
                import io
                old_stdout = sys.stdout
                sys.stdout = capture = io.StringIO()
                try:
                    invoke_search(query)
                finally:
                    sys.stdout = old_stdout
                
                search_out = capture.getvalue()
                lines = [l.strip() for l in search_out.splitlines() if l.startswith("Found: ")]
                
                if not lines:
                    print(f"  {Colors.YELLOW}[warn] No patches found for '{query}'.{Colors.RESET}")
                else:
                    identifiers = []
                    options = []
                    for line in lines:
                        match = re.match(r'Found: (\S+)', line)
                        if match:
                            ident = match.group(1)
                            identifiers.append(ident)
                            options.append(line)
                    options.append("Cancel")

                    select_idx = read_menu_selection("Select Patch to Fetch", options)
                    if select_idx != -1 and select_idx < len(identifiers):
                        selected_id = identifiers[select_idx]
                        
                        try: clear_screen()
                        except Exception: pass
                        draw_header()
                        
                        draw_box_top("Fetch Selected Patch")
                        out_dir = read_text_input("Enter output folder", default=".")
                        if out_dir is not None:
                            draw_box_bottom()
                            # Match prefix details
                            match_slug = re.match(r'(?:gpatcher|popayarip)-([a-zA-Z0-9\-]+)-([a-zA-Z0-9\.\-]+)-to-([a-zA-Z0-9\.\-]+)', selected_id)
                            if match_slug:
                                slug = match_slug.group(1)
                                from_v = match_slug.group(2)
                                to_v = match_slug.group(3)
                                print(f"\n  {Colors.YELLOW}> Fetching patch {selected_id}...{Colors.RESET}")
                                invoke_fetch(slug, from_v, to_v, out_dir=out_dir)
                            else:
                                print(f"  {Colors.RED}[err] Invalid patch identifier format: {selected_id}{Colors.RESET}")
            except Exception as e:
                log_err(f"Search & Fetch failed: {e}")

        elif selection == 4:  # Verify Installation
            draw_box_top("Verify Installation")
            install = read_path_input("Enter install directory", must_exist=True, is_directory=True)
            if install is None: continue
            against = read_path_input("Enter manifest.json or patch ZIP path", must_exist=True)
            if against is None: continue
            draw_box_bottom()

            print(f"\n  {Colors.YELLOW}> Verifying installation...{Colors.RESET}")
            try:
                invoke_verify(install, against)
            except Exception as e:
                log_err(f"Verification failed: {e}")

        elif selection == 5:  # Diagnostics (Doctor)
            draw_box_top("System Diagnostics")
            draw_box_bottom()
            invoke_doctor()

        elif selection == 6:  # Fetch Binaries
            draw_box_top("Fetch Dependencies")
            draw_box_bottom()
            print(f"\n  {Colors.YELLOW}> Downloading HDiffPatch binaries...{Colors.RESET}")
            try:
                from gpatcher.tools.fetch import fetch_hdiffpatch
                fetch_hdiffpatch()
            except Exception as e:
                log_err(f"Fetch failed: {e}")

        elif selection == 7:  # Check / Install gpatcher updates
            draw_box_top("Check for updates")
            draw_box_bottom()
            force = read_confirm_choice("Force update check/re-install?", default=False)
            if force is not None:
                print(f"\n  {Colors.YELLOW}> Checking for updates...{Colors.RESET}")
                try:
                    from gpatcher.core.update import invoke_update
                    invoke_update(force=force)
                except Exception as e:
                    log_err(f"Update failed: {e}")

        if running:
            sys.stdout.write(f"\n  {Colors.GRAY}Press Enter to return to main menu...{Colors.RESET}")
            sys.stdout.flush()
            sys.stdin.readline()

def main():
    invoke_interactive_menu()

if __name__ == '__main__':
    main()
