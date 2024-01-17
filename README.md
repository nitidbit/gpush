gPush
=====
This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

Installation
===========================

(tbd)


What actually happens during gPush?
================

![Flow](https://github.com/nitidbit/gpush/blob/release/v2-hackathon/gpush_diagram.png?raw=true)

Developer Setup
---------------

### Python
You should already have Python 3 installed. It comes by default with MacOS, but you can
also get new version with Brew

### Libraries
    cd gpush
    pip3 install -r requirements.txt

### Run
    ./gpush.py
