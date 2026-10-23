# Drift Coach

Record a drift run, then practise alongside a ghost car and a painted driving line in Assetto Corsa.

## Features

- **Ghost car:** follow a recorded run at its original pace.
- **Painted line:** see the route and where throttle, brake, handbrake and clutch were used.
- **Saved runs:** name, select, rename and delete recordings for each track, layout and car.
- **Pedal comparison:** the compatible Drift HUD shows recorded inputs alongside your live inputs.
- **Coach camera:** an elevated chase view that follows the direction of travel to make the car's angle against the road easier to see.

## Install

Requires **Assetto Corsa**, **Content Manager** and **CSP with Lua apps and scripted chase cameras**.

1. Close the driving session.
2. Copy `apps/` and `extension/` into your Assetto Corsa game folder, merging them with the existing folders.
3. Check that `apps/lua/DriftCoach/DriftCoach.lua` exists inside the game folder.
4. Enable **Drift Coach** if listed in Content Manager's app settings, then start a session.
5. Open **Drift Coach** from the in-game app sidebar.

For the included camera, open **Settings → Custom Shaders Patch → Chase Camera** in Content Manager, enable it and select **Drift Coach**. Use a chase view in-game. The app also works with other camera choices.

## Record and practise

1. Enter a recording name and click **Record**.
2. Drive your run, then click **Stop and save**. Runs shorter than a second are discarded.
3. Click **Use** beside a saved run to make it your reference.
4. Return to the white start circle and drive through it to release the ghost.
5. Click **Reset ghost** to prepare another attempt.

The painted line uses **green for throttle**, **red for brake**, **purple for handbrake** and **blue circles for clutch kicks**. The app shows your time gap and slip-angle difference when you are near the recorded line. The ghost's wheels do not animate steering.

Recordings are stored under `Documents/Assetto Corsa/drift-coach/`, grouped by track, layout and car. Use the same combination to load them again.

## Make it yours

In **Drift Coach Settings**, you can:

- Toggle the painted line and ghost separately.
- Adjust line opacity and the start circle radius.
- Bind controls for recording and resetting the ghost.

Tune the included camera in CSP's **Chase Camera** settings: distance, height, field of view, look-ahead, travel-direction follow, smoothing and horizon stability.

The optional **Drift HUD** integration requires a version with Drift Coach support. Drift HUD is installed separately.

## Updating or removing

Replace the mod's app and camera folders to update, then restart the session.

To uninstall, select another chase camera and delete only `apps/lua/DriftCoach/` and `extension/lua/chaser-camera/drift-coach/`. Saved recordings are kept separately in Documents.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): use, modify and share for noncommercial purposes under its terms. Commercial use needs separate permission. [Third-party notices](NOTICE.md).
