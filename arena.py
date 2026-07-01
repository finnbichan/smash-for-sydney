import melee

from fight import fight
from bots.example import Example

import logging
logging.basicConfig(level=logging.DEBUG)

if __name__ == "__main__":
    player1 = Example(melee.Character.MARIO)
    player2 = Example(melee.Character.KIRBY)

    fight(melee.Stage.RANDOM_STAGE, [player1, player2])