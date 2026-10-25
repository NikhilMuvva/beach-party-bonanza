"""App rename must keep camera preview and launcher profile colocated."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('frat_launch', ROOT / 'launch.py')
launch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch)

class LauncherProfileTests(unittest.TestCase):
    def test_renamed_profile_matches_godot_app(self):
        self.assertEqual(launch.default_profile().parent.name, 'Frat Flicks')
        self.assertIn('config/name="Frat Flicks"', (ROOT / 'project.godot').read_text())

if __name__ == '__main__':
    unittest.main()

class WindowsDiscoveryTests(unittest.TestCase):
    def test_py_launcher_discovers_supported_versions(self):
        from unittest.mock import patch
        from types import SimpleNamespace
        with patch.object(launch.shutil, 'which', return_value='py'), patch.object(launch.subprocess, 'run', side_effect=[SimpleNamespace(returncode=0,stdout='C:/Python311/python.exe\n'),SimpleNamespace(returncode=1,stdout='')]) as run:
            result=launch.windows_python_candidates()
        self.assertEqual(result,[Path('C:/Python311/python.exe')])
        self.assertEqual(run.call_args_list[0].args[0][1],'-3.11')
