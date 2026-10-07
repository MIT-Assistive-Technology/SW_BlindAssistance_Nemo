import sys
from pathlib import Path

# Make `import app...` work when running `pytest` from server/.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
