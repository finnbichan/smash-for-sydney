import sys
import signal
import melee
import logging
import os
from pathlib import Path

PREREQS_DIR = Path("./prereqs")
SLIPPI_LAUNCHER_DIR = Path.home() / ".config" / "Slippi Launcher"
DOLPHIN_EXECUTABLES = (
    "Slippi_Online-x86_64.AppImage",
    "Slippi_Netplay_Mainline-x86_64.AppImage",
)
ISO = PREREQS_DIR / "Super Smash Bros. Melee (USA) (En,Ja) (Rev 2)" / "Super Smash Bros. Melee (USA) (En,Ja) (Rev 2).nkit.iso"


def resolve_slippi_path():
    configured_path = os.environ.get("SMASH_SLIPPI_PATH")
    if configured_path:
        return configured_path

    candidates = []
    for executable in DOLPHIN_EXECUTABLES:
        candidates.append(PREREQS_DIR / executable)

    candidates.extend(
        (
            SLIPPI_LAUNCHER_DIR / "netplay-beta",
            SLIPPI_LAUNCHER_DIR / "netplay",
        )
    )

    for path in candidates:
        if path.is_file() or path.is_dir():
            return str(path)

    raise FileNotFoundError(
        "Could not find Slippi Dolphin. Install Slippi through the launcher so "
        f"{SLIPPI_LAUNCHER_DIR / 'netplay'} or {SLIPPI_LAUNCHER_DIR / 'netplay-beta'} exists, "
        f"or copy one of these files into {PREREQS_DIR}: {', '.join(DOLPHIN_EXECUTABLES)}. "
        "The Slippi Launcher AppImage is only the installer/launcher, not the Dolphin "
        "executable libmelee needs. You can also set SMASH_SLIPPI_PATH to the Dolphin "
        "executable or install directory."
    )


def resolve_iso_path():
    configured_path = os.environ.get("SMASH_ISO_PATH")
    path = Path(configured_path) if configured_path else ISO

    if path.is_file():
        return str(path)

    raise FileNotFoundError(
        f"Could not find the Melee ISO at {path}. Set SMASH_ISO_PATH to the ISO file "
        f"or place it at {ISO}."
    )

def fight(stage, players):

    console = melee.Console(path=resolve_slippi_path(), fullscreen=True)

    port = 1
    for player in players:
        player.create_controller(console, port)
        port += 1

    def signal_handler(sig, frame):
        for player in players:
            player.controller.disconnect()
        console.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    console.run(iso_path=resolve_iso_path())

    logging.info("Connecting to console...")
    if not console.connect():
        logging.error("ERROR: Failed to connect to the console.")
        sys.exit(-1)
    logging.info("Console connected")

    for player in players:
        player.connect()

    menu_helper = melee.MenuHelper()

    while True:

        gamestate = console.step()
   
        if gamestate.menu_state in [melee.Menu.IN_GAME, melee.Menu.SUDDEN_DEATH]:
            for player in players:
                player.fight(gamestate)
        else:
            for player in players:
                menu_helper.menu_helper_simple(
                gamestate,
                player.controller,
                player.character,
                stage,
                "",
                autostart=True,
                swag=False)
