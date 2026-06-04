import os
import sys
import shutil
import tempfile

GPATCHER_VERSION = '0.3.1'

# Console text colors (ANSI Escape Codes)
class Colors:
    CYAN = '\033[96m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    GREEN = '\033[92m'
    MAGENTA = '\033[95m'
    GRAY = '\033[90m'
    WHITE = '\033[97m'
    RESET = '\033[0m'
    BG_MAGENTA = '\033[45m'

def log_info(msg: str):
    print(f"{Colors.CYAN}[info]  {msg}{Colors.RESET}")

def log_warn(msg: str):
    print(f"{Colors.YELLOW}[warn]  {msg}{Colors.RESET}")

def log_err(msg: str):
    print(f"{Colors.RED}[err]   {msg}{Colors.RESET}")

def log_ok(msg: str):
    print(f"{Colors.GREEN}[ok]    {msg}{Colors.RESET}")

def get_app_data_dir() -> str:
    """Returns the platform-specific user application data directory for gpatcher."""
    if sys.platform == 'win32':
        base = os.environ.get('LOCALAPPDATA') or os.environ.get('APPDATA') or os.path.expanduser('~')
        return os.path.join(base, 'gpatcher')
    elif sys.platform == 'darwin':
        return os.path.expanduser('~/Library/Application Support/gpatcher')
    else:
        return os.path.expanduser('~/.gpatcher')

def get_bin_path(name: str) -> str:
    """Returns the absolute path to a binary inside the gpatcher bin/ directory."""
    return os.path.join(get_app_data_dir(), 'bin', name)

def get_relative_path(root: str, full_path: str) -> str:
    """Returns the slash-normalized path of full_path relative to root."""
    root_abs = os.path.abspath(root).rstrip(os.path.sep)
    full_abs = os.path.abspath(full_path)
    if not full_abs.startswith(root_abs):
        raise ValueError(f"Path {full_path} is not under root {root}")
    rel = full_abs[len(root_abs):].lstrip(os.path.sep)
    return rel.replace(os.path.sep, '/')

def to_native_path(rel_path: str) -> str:
    """Converts a slash-normalized relative path to the native platform path separator."""
    return rel_path.replace('/', os.path.sep)

def new_temp_dir(prefix: str = 'gpatcher-') -> str:
    """Creates a temporary directory and returns its absolute path."""
    return tempfile.mkdtemp(prefix=prefix)

def remove_path_safe(path: str):
    """Safely removes a file or directory recursively if it exists."""
    if not os.path.exists(path):
        return
    try:
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    except Exception:
        pass

def format_bytes(bytes_count: int) -> str:
    """Formats a byte count into a human-readable string (KB, MB, GB, etc.)."""
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    val = float(bytes_count)
    i = 0
    while val >= 1024.0 and i < len(units) - 1:
        val /= 1024.0
        i += 1
    return f"{val:.2f} {units[i]}"

def assert_not_reparse(path: str):
    """Asserts that a path is not a symlink/junction/reparse point."""
    if os.path.islink(path):
        raise ValueError(f"Symlink/junction not supported: {path}")
