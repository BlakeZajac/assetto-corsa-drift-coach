"""Render the real Lua HUD with sample telemetry; requires lupa and Pillow."""
import argparse
import os
from pathlib import Path
from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT_CANDIDATES = [Path('C:/Windows/Fonts/segoeui.ttf'), Path('/System/Library/Fonts/Helvetica.ttc'), Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]


def preview(output=None, coach=False):
    os.chdir(ROOT)
    output = Path(output or ROOT / 'dist/drift-hud-preview.png')
    output.parent.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'apps/lua/DriftHUD'
    if not source.exists():
        source = ROOT / 'csp/apps/lua/DriftHUD'
    font_path = next((p for p in FONT_CANDIDATES if p.exists()), None)
    if font_path is None:
        raise RuntimeError('Install Segoe UI, Helvetica or DejaVu Sans for previews')
    image = Image.new('RGB', (2168 if coach else 1760, 228), '#101822')
    draw = ImageDraw.Draw(image, 'RGBA')
    lua = LuaRuntime(unpack_returned_tuples=True)
    origin = [30, 88]
    available = [400, 92]
    fonts = {}

    def font(size):
        size = max(1, round(size))
        if size not in fonts:
            fonts[size] = ImageFont.truetype(str(font_path), size)
        return fonts[size]

    def point(p):
        return p['x'] + origin[0], p['y'] + origin[1]

    def color(c):
        return tuple(round(max(0, min(1, c[k])) * 255) for k in ('r', 'g', 'b', 'mult'))

    def rect(a, b, c, radius=0):
        coords = (*point(a), *point(b))
        if coords[2] > coords[0] and coords[3] > coords[1]:
            draw.rounded_rectangle(coords, radius=max(0, radius), fill=color(c))

    def text(value, size, pos, c):
        draw.text(point(pos), str(value), font=font(size), fill=color(c), anchor='lt')

    def measure(value, size):
        return lua.table_from({'x': font(size).getlength(str(value)), 'y': size})

    def line(a, b, c, width=1):
        draw.line((*point(a), *point(b)), fill=color(c), width=max(1, round(width)))

    def circle(pos, radius, c, segments=40, width=1):
        x, y = point(pos)
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), outline=color(c), width=max(1, round(width)))

    lua.globals().ui = lua.table_from({
        'drawRectFilled': rect, 'drawLine': line, 'drawCircle': circle,
        'dwriteDrawText': text, 'measureDWriteText': measure,
        'getCursor': lambda: lua.table_from({'x': 0, 'y': 0}),
        'availableSpace': lambda: lua.table_from({'x': available[0], 'y': available[1]}),
        'setCursor': lambda *_: None, 'dummy': lambda *_: None,
    })
    lua.globals().sourcePath = source.as_posix()
    lua.execute('''
      package.path = sourcePath .. '/?.lua;' .. package.path
      vec2 = function(x,y) return {x=x,y=y} end
      rgbm = function(r,g,b,a) return {r=r,g=g,b=b,mult=a} end
      local T = require('telemetry')
      sampleState = T.new()
      sampleCar = {velocity={x=10,z=20},look={x=0,z=1},speedKmh=80.5,gear=3,rpm=6240,
        rpmLimiter=7500,fuel=23.5,steer=-146,gas=.73,brake=0,clutch=1,handbrake=0,
        ffbFinal=.42,turboBoost=.6,physicsAvailable=true,wheels={}}
      for i=0,3 do sampleCar.wheels[i]={tyreCoreTemperature=76+i*4,tyrePressure=27+i*.4,
        tyreInsideTemperature=78+i*4,tyreMiddleTemperature=76+i*4,tyreOutsideTemperature=74+i*4} end
      for n=1,160 do
        sampleCar.gas = .55 + .4 * math.sin(n*.12)
        sampleCar.brake = math.max(0,math.sin(n*.19))*.25
        T.update(sampleState,sampleCar,.05,false,false,true)
      end
      sampleState.last={seconds=12.8,transitions=3,peak=48}
      sampleState.trackBest=sampleState.last
      samplePrefs={backgroundOpacity=.35,graph=true,tyres=true,drift=true,
        driving=true,steering=true,inputs=true,invertClutch=true}
      for i=1,6 do samplePrefs['trace'..i]=true end
    ''')
    if coach:
        lua.execute('''
          sampleCar.gas, sampleCar.brake = .35, .05
          sampleState.coach = {status=2,gas=.6,brake=.2,speed=78,gear=3,
            cue=1,cueIn=.8,gasTrend=0,brakeTrend=1}
          sampleState.ghost = {.6,.2,0,0,-140}
        ''')
    view = lua.eval("require('view')")
    modes = [('graph', 'INPUT HISTORY'), (None, 'DRIVING / INPUTS / DRIFT'), ('tyres', 'TYRES')]
    x = 30
    for mode, label in modes:
        width, height = view.size(lua.globals().samplePrefs, mode, coach)
        origin[:] = [x, 88]
        available[:] = [width, height]
        draw.text((x, 62), label, font=font(11), fill='#7e929e')
        view.draw(lua.globals().sampleCar, lua.globals().sampleState, lua.globals().samplePrefs, width, False, mode)
        x += width + 8
    draw.text((30, 15), 'DRIFT HUD', font=font(23), fill='#ecf3f6')
    draw.text((30, 197), 'Rendered from the Lua view with sample data. Game font rendering can differ.', font=font(12), fill='#8e9eaa')
    image.save(output)
    print(output)
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--coach', action='store_true', help='Include the demo / learner comparison')
    args = parser.parse_args()
    preview(args.output, args.coach)
