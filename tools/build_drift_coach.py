"""Package Drift Coach with the matching HUD; exclude all car and vendor assets."""
import configparser
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    'DriftCoach': ['manifest.ini', 'DriftCoach.lua', 'recorder.lua', 'playback.lua',
                   'runs.lua', 'paint.lua', 'ghost.lua', 'coaching.lua', 'lesson.lua', 'visuals.lua'],
    'DriftHUD': ['manifest.ini', 'DriftHUD.lua', 'telemetry.lua', 'view.lua', 'history.lua', 'layout.lua'],
}


def build():
    config = configparser.ConfigParser(strict=False)
    config.read(ROOT / 'apps/lua/DriftCoach/manifest.ini')
    destination = ROOT / 'dist' / f"drift-coach-v{config['ABOUT']['VERSION']}-with-hud.zip"
    destination.parent.mkdir(exist_ok=True)
    payload = {}
    for app, names in FILES.items():
        for name in names:
            relative = f'apps/lua/{app}/{name}'
            payload[relative] = (ROOT / relative).read_bytes()
    for name in ['camera.lua', 'manifest.ini', 'settings.ini']:
        relative = f'extension/lua/chaser-camera/drift-coach/{name}'
        payload[relative] = (ROOT / relative).read_bytes()
    for name in ['LICENSE.md', 'NOTICE.md']:
        payload[name] = (ROOT / name).read_bytes()
    with ZipFile(destination, 'w', ZIP_DEFLATED) as archive:
        for name, data in payload.items():
            archive.writestr(name, data)
    with ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == set(payload)
        for name, data in payload.items():
            assert archive.read(name) == data
    print(destination)
    return destination


if __name__ == '__main__':
    build()
