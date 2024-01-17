#!/usr/bin/env python
# encoding: utf-8

import sys
import curses
import npyscreen
import os.path

from os import system, name
from pathlib import Path

class bcolors:
    OK      = '\033[92m'
    FAIL    = '\033[91m'
    RESET   = '\u001b[0m'
    DEFAULT = '\033[35m'
    CHECK   = '\033[33m'
    PINK    = '\033[95m'

def clear():
    if name == 'nt':
        _ = system('cls')
    else:
        _ = system('clear')


hostnames = ["1.1.1.1", "0.0.0.0", "2.2.2.2"]

class dashboard(npyscreen.NPSApp):
    def main(self):
        F  = npyscreen.Form(name = "DASHBOARD")
        column_height = terminal_dimensions()[0] -9
        widget_top = F.add(
            Column,
            name        = "SERVER",
            relx        = 2,
            rely        = 2,
            max_width   = 40,
        )

        widget_top.values = [print(re)]
        F.edit()

class Column(npyscreen.BoxTitle):
    def resize(self):
        self.max_height = int(0.73 * terminal_dimensions()[0])

def terminal_dimensions():
    return curses.initscr().getmaxyx()

def ping():
    for i in hostnames:
        response = os.system("ping -c 1 " + i + "> /dev/null 2>&1")
        if response == 0:
            print(bcolors.OK + "" + bcolors.RESET + f" {i}")
        else:
            print(bcolors.FAIL + "" + bcolors.RESET + f" {i}")

re = ping()

if __name__ == "__main__":
    clear()
    App = dashboard()
    App.run()
