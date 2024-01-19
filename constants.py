# Shared constants and simple types


# Ansi escape codes
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
RESET = "\033[0m"

class GpushError(RuntimeError):
    """
    Raise this error, and the message will be printed to console, and program aborted.
    No stack trace
    """
    pass
