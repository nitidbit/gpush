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


#hostnames = ["1.1.1.1", "0.0.0.0", "2.2.2.2"]
commands = ["rspec", "jest"]

class dashboard(npyscreen.NPSApp):
    def main(self):
        F  = npyscreen.Form(name = "GPUSH DASHBOARD")
        print("hello"*5)
        column_height = terminal_dimensions()[0] -9
        widget_top = F.add(
            Column,
            name        = "JAY's SERVER",
            relx        = 2,
            rely        = 2,
            max_width   = 40,
        )

        widget_top.values = [print(re)]
        F.edit()
        F.display()

class Column(npyscreen.BoxTitle):
    def resize(self):
        self.max_height = int(0.73 * terminal_dimensions()[0])

def terminal_dimensions():
    return (23, 20) #curses.initscr().getmaxyx()

def ping():
    for i in commands:
#        response = os.system("ping -c 1 " + i + "> /dev/null 2>&1")
        response = os.system("ps au" + i + "> /dev/null 2>&1")
        print(i)
#        if response == 0:
#            print(bcolors.OK + "" + bcolors.RESET + f" {i}")
#        else:
#            print(bcolors.FAIL + "" + bcolors.RESET + f" {i}")


re = ping()

if __name__ == "__main__":
    clear()
    App = dashboard()
    App.run()
