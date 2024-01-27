#!/bin/sh
trap "" SIGWINCH
/entrypoint.sh apache2-foreground
