import melee
import logging
import random

from .bot import Bot

class Masher(Bot):

    def __init__(self, character=None):

        character = random.choice([x for x in melee.enums.Character])
        super().__init__(character)
        
        self.buttons = [x for x in melee.enums.Button]
        self.buttons.remove(melee.enums.Button.BUTTON_MAIN)
        self.buttons.remove(melee.enums.Button.BUTTON_START)

    def fight(self, gamestate):

        if random.random() < 0.5:
            self.controller.press_button(random.choice(self.buttons))
        else:
            self.controller.release_all()
