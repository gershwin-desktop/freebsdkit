#!/bin/sh

sudo rm -rf /System/Library/Frameworks/FreeBSDKit.framework
sudo rsync -rav ./FreeBSDKit.framework /System/Library/Frameworks/

exit
