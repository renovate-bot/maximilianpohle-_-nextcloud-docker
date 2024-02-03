#!/bin/bash
trap "" SIGWINCH
/entrypoint.sh apache2-foreground
