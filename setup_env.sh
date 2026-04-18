#!/usr/bin/env bash
# Source this file before running ibex DV simulations:
#   source setup_env.sh
#
# Overrides SPIKE_PATH and PKG_CONFIG_PATH to use the ibex-cosim Spike fork,
# which provides ibex-specific processor APIs required by the co-simulation DPI.
# Standard Spike (in RISCV_TOOLCHAIN) remains available for other projects.

IBEX_SPIKE_DIR="/data/bwq_main/toolchain/ibex_spike"

export SPIKE_PATH="$IBEX_SPIKE_DIR/bin"
export PKG_CONFIG_PATH="$IBEX_SPIKE_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

echo "ibex-cosim spike activated: $SPIKE_PATH"
