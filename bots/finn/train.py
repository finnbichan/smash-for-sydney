"""
bots/finn/train.py

Trains bots/finn/bot.py via PPO (stable-baselines3), against another Bot from
this repo as the opponent (defaults to bots.example.Example).

Why this isn't just a variant of fight.py: fight() is a per-frame,
side-effecting callback with no return value - it can't hand PPO an
observation/reward/done tuple to step through. This script runs its own
console loop instead, using the same env vars and Console/menu setup
convention as fight.py, but wrapped as a Gymnasium environment.

Env vars (same as the rest of this repo, see fight.py):
    SMASH_SLIPPI_PATH - optional path to the Slippi Dolphin binary/install dir
    SMASH_ISO_PATH    - optional path to the Melee ISO

Usage:
    source env.sh   # or env.cmd / env.ps1 on Windows, as set up by setup-*.sh
    python -m bots.finn.train --timesteps 100000

To train against a different opponent (e.g. a ported SmashBot once added to
bots/), pass a different Bot instance to TrainingEnv(opponent_bot=...) below.
"""

import argparse
import logging
import numpy as np
import melee
import gymnasium as gym
from gymnasium import spaces
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback

from bots.linyu import LinyuPikachu
from bots.masher import Masher
from bots.smashbot import SmashBot
from fight import resolve_iso_path, resolve_slippi_path
from bots.finn.actions import (
    ACTIONS,
    AGENT_CHARACTER,
    N_ACTIONS,
    OBS_SIZE,
    apply_action,
    compute_reward,
    get_observation,
)
from bots.example import Example


class TrainingEnv(gym.Env):
    """
    Drives one Dolphin/Slippi instance with the RL agent on port 1 and a
    scripted opponent Bot on port 2. Each step() call advances one frame.
    """

    metadata = {"render_modes": []}

    def __init__(self, opponent_bot=None, stage=melee.Stage.FINAL_DESTINATION):
        super().__init__()
        slippi_path = resolve_slippi_path()
        iso_path = resolve_iso_path()

        self.stage = stage
        self.agent_character = AGENT_CHARACTER
        self.opponent_bot = opponent_bot or LinyuPikachu(melee.Character.KIRBY)

        self.action_space = spaces.Discrete(N_ACTIONS)
        self.observation_space = spaces.Box(low=-1e4, high=1e4, shape=(OBS_SIZE,), dtype=np.float32)

        self.agent_port = 1
        self.opponent_port = 2

        self.console = melee.Console(path=slippi_path, fullscreen=False, emulation_speed=0.0)
        self.controller = melee.Controller(console=self.console, port=self.agent_port)
        self.opponent_bot.create_controller(self.console, self.opponent_port)

        self.console.run(iso_path=iso_path)
        logging.info("Connecting to console...")
        if not self.console.connect():
            raise RuntimeError("Failed to connect to the console")
        logging.info("Console connected")
        self.controller.connect()
        self.opponent_bot.connect()

        self.menu_helper = melee.MenuHelper()
        self.prev_gamestate = None
        self._current_action = "no_op"
        self._frame_in_action = 0

    def _in_game(self, gamestate) -> bool:
        return gamestate.menu_state in [melee.Menu.IN_GAME, melee.Menu.SUDDEN_DEATH]

    def _navigate_menus(self, gamestate):
        while not self._in_game(gamestate):
            self.menu_helper.menu_helper_simple(
                gamestate, self.controller, self.agent_character, self.stage, "",
                autostart=True, swag=False,
            )
            self.menu_helper.menu_helper_simple(
                gamestate, self.opponent_bot.controller, self.opponent_bot.character, self.stage, "",
                autostart=True, swag=False,
            )
            gamestate = self.console.step()
        return gamestate

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        gamestate = self.console.step()
        gamestate = self._navigate_menus(gamestate)
        self.prev_gamestate = gamestate
        self._current_action = "no_op"
        self._frame_in_action = 0
        obs = get_observation(gamestate, self.agent_port, self.opponent_port)
        return np.array(obs, dtype=np.float32), {}

    def step(self, action_idx):
        action = ACTIONS[int(action_idx)]
        if action == self._current_action:
            self._frame_in_action += 1
        else:
            self._frame_in_action = 0
            self._current_action = action

        apply_action(self.controller, action, self._frame_in_action)
        # Opponent acts on the same gamestate the agent just acted on,
        # mirroring the per-frame ordering in fight.py.
        self.opponent_bot.fight(self.prev_gamestate)

        gamestate = self.console.step()

        reward = compute_reward(self.prev_gamestate, gamestate, self.agent_port, self.opponent_port)
        terminated = not self._in_game(gamestate)
        if terminated:
            obs = get_observation(self.prev_gamestate, self.agent_port, self.opponent_port)
            self.prev_gamestate = gamestate
            return np.array(obs, dtype=np.float32), reward, True, False, {}

        obs = get_observation(gamestate, self.agent_port, self.opponent_port)

        agent_died = gamestate.players[self.agent_port].stock < self.prev_gamestate.players[self.agent_port].stock
        self.prev_gamestate = gamestate

        return np.array(obs, dtype=np.float32), reward, agent_died, False, {}

    def close(self):
        self.controller.disconnect()
        self.opponent_bot.controller.disconnect()
        self.console.stop()


def main():
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument("--timesteps", type=int, default=100_000)
    parser.add_argument("--checkpoint-freq", type=int, default=5_000,
                         help="Save every N env steps - keep low given a short training budget")
    parser.add_argument("--checkpoint-dir", default="checkpoints")
    parser.add_argument("--resume-from", default=None,
                         help="Path to an existing .zip checkpoint to continue training from")
    args = parser.parse_args()

    env = TrainingEnv()

    if args.resume_from:
        model = PPO.load(args.resume_from, env=env)
        logging.info(f"Resumed from {args.resume_from}")
    else:
        model = PPO(
            "MlpPolicy",
            env,
            verbose=1,
            n_steps=1024,      # smaller than SB3's 2048 default - fewer frames per
                               # update given Dolphin's ~1-2x realtime speed, so you
                               # actually see updates land within a short session
            batch_size=64,
            learning_rate=3e-4,
            tensorboard_log="./tb_logs",
            device="cpu"
        )

    checkpoint_callback = CheckpointCallback(
        save_freq=args.checkpoint_freq,
        save_path=args.checkpoint_dir,
        name_prefix="melee_ppo",
    )

    try:
        model.learn(total_timesteps=args.timesteps, callback=checkpoint_callback)
    except KeyboardInterrupt:
        logging.info("Interrupted - saving current weights before exit.")
    finally:
        model.save(f"{args.checkpoint_dir}/model_final")
        env.close()
        logging.info(f"Saved final weights to {args.checkpoint_dir}/model_final.zip")


if __name__ == "__main__":
    main()
