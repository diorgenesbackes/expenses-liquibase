"""Compatibility entry point; non-unit tests live in expenses-tests."""
from pathlib import Path
import runpy
import sys

scripts = Path(__file__).resolve().parents[2] / 'expenses-tests/scripts'
sys.path.insert(0, str(scripts))
runpy.run_path(str(scripts / 'schema.py'), run_name='__main__')
