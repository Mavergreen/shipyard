#!/bin/sh
pkgbuild --root stage --identifier dev.mavergreen.w out.pkg
sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr
