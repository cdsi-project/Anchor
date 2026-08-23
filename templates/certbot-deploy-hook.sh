#!/bin/sh
# Reload Nginx only after the renewed configuration passes validation.

set -eu

nginx -t
systemctl reload nginx
