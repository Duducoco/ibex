# Ibex RISC-V Core - Project Context

## Project Overview

Ibex is an open-source 32-bit RISC-V CPU core (RV32IMC/EMC) from lowRISC.
Build system: Make + Python + FuseSoC. Verification: UVM + riscv-dv + Spike cosim.

## Key Directory Structure

```
rtl/                          # RTL source code
dv/                           # Design Verification
  cosim/                      # Spike DPI cosimulation (cosim_dpi.cc, spike_cosim.cc)
  cs_registers/               # CSR register testbench
  formal/                     # Formal verification (Yosys, conductor.py)
  riscv_compliance/           # RISC-V compliance tests
  uvm/                        # UVM verification environment
    core_ibex/                # *** Main DV testbench ***
      Makefile                # Top-level entry (config knobs)
      wrapper.mk              # Dependency tree (11-stage pipeline)
      yaml/rtl_simulation.yaml  # Simulator command templates (vcs/xlm/questa/dsim/riviera)
      riscv_dv_extension/     # Ibex custom target for riscv-dv
        testlist.yaml         # ~50+ test definitions
        csr_description.yaml  # CSR descriptions
        riscv_core_setting.tpl.sv  # Mako template → riscv_core_setting.sv
        ibex_asm_program_gen.sv    # Custom asm program generator
      env/                    # UVM env, scoreboard, interfaces
      tests/                  # UVM test library
      common/                 # UVM agents (cosim, mem_intf, irq)
      scripts/                # Python automation (metadata, compile, run, check)
      directed_tests/         # Directed test list and sources
      fcov/                   # Functional coverage
    icache/                   # ICache standalone DV
  verilator/                  # Verilator simulation
vendor/
  google_riscv-dv/            # Google riscv-dv (random instruction generator)
  lowrisc_ip/                 # lowRISC IP library (dvsim, DV tools)
doc/                          # Documentation (RST format)
examples/simple_system/       # Simple system example
ibex_configs.yaml             # Hardware configs (small, opentitan, maxperf, etc.)
```

## VCS + riscv-dv Random Verification Flow

### Entry Command

```bash
cd dv/uvm/core_ibex
make SIMULATOR=vcs ISS=spike IBEX_CONFIG=opentitan TEST=<test_name> SEED=<seed> COV=1
```

Key params: SIMULATOR (vcs/xlm/questa/dsim), ISS (spike/ovpsim), IBEX_CONFIG, TEST, SEED, COV, WAVES, ITERATIONS.

### 11-Stage Pipeline (wrapper.mk)

1. **create_metadata** (metadata.py) - Parse args → RegressionMetadata pickle
2. **core_config** (render_config_template.py) - Mako template → riscv_core_setting.sv
3. **instr_gen_build** (build_instr_gen.py) - Compile riscv-dv SV instruction generator via SIMULATOR
4. **instr_gen_run** (run_instr_gen.py) - Run generator → test.S assembly files
5. **compile_test** (compile_test.py) - RISC-V GCC: test.S → test.bin
6. **rtl_tb_compile** (compile_tb.py) - Compile RTL+UVM testbench via SIMULATOR (parallel with step 5)
7. **rtl_sim_run** (run_rtl.py) - Run RTL simulation with Spike cosim
8. **check_logs** (check_logs.py) - Parse logs, determine pass/fail
9. **riscv_dv_fcov** (get_fcov.py) - Generate riscv-dv functional coverage
10. **merge_cov** (merge_cov.py) - Merge coverage databases
11. **collect_results** (collect_results.py) - Generate HTML/JUnit/text reports

### VCS Specifics (rtl_simulation.yaml)

- **Compile**: `vcs -full64 -sverilog -ntb_opts uvm-1.2` + cosim DPI + Spike link flags (via pkg-config)
- **Simulate**: `vcs_simv +ntb_random_seed=<seed> +UVM_TESTNAME=<rtl_test> +bin=<binary>`
- **Coverage**: `-cm line+tgl+assert+fsm+branch`, per-test VDB, merged at end
- **VCS quirk**: Does not support `-l` for log file; `run_rtl.py` uses stdout redirect instead (line 96-97)
- **Cosim DPI**: Always enabled; links Spike via `-f ibex_dv_cosim_dpi.f`

### Spike Cosimulation (Correctness)

RTL outputs instruction trace via RVFI interface → DPI-C calls Spike → per-instruction comparison of PC, register writes, CSR updates, memory accesses.

Key files: `dv/cosim/cosim_dpi.cc`, `dv/cosim/spike_cosim.cc`, `dv/uvm/core_ibex/common/ibex_cosim_agent/`

### riscv-dv Integration

- Custom target: `dv/uvm/core_ibex/riscv_dv_extension/`
- `riscvdv_interface.py`: Parses YAML templates, substitutes `<placeholder>` variables, returns shell commands
- `testlist.yaml` defines each test: gen_test, gen_opts, rtl_test, sim_opts, iterations
- The SV instruction generator itself is compiled+run using the same SIMULATOR

### Configuration System

- `ibex_configs.yaml`: Hardware parameter sets (opentitan, small, maxperf, experimental-branch-predictor)
- `riscv_core_setting.tpl.sv`: Mako template that maps Ibex config → riscv-dv ISA settings
- `rtl_simulation.yaml`: Per-simulator command templates with `<placeholder>` substitution

### TEST Parameter and Test Selection

The `TEST` parameter controls which tests to run. **Important**: `TEST=all` does NOT run all tests — it only runs random (riscv-dv) tests.

| TEST Value | Scope |
|------------|-------|
| `all` (default) | Random tests only (`testlist.yaml`) |
| `all_riscvdv` | Same as `all` — random tests only |
| `all_directed` | Directed tests only (`directed_testlist.yaml`) |
| `all,all_directed` | **Both** random and directed tests |
| `<test_name>` | Specific test by name (matches either testlist) |
| `<name1>,<name2>` | Multiple specific tests (comma-separated) |

The logic is in `metadata.py`:
- Random tests (`process_riscvdv_testlist`): matches `all` or `all_riscvdv` (line 307)
- Directed tests (`process_directed_testlist`): matches `all_directed` only, **not** `all` (line 326-327)

### Test Categories

- Arithmetic, random instruction, jump stress, loop, MMU stress
- Illegal instruction, hint instruction, CSR operations
- PMP (Physical Memory Protection)
- Debug mode, debug triggers
- Interrupt (WFI, nested, CSR)
- Compressed instructions (RV32C)
- Bit manipulation (RV32B) when enabled
- Memory error injection (SecureIbex)

## Code Conventions

- RTL: SystemVerilog, `ibex_` prefix for modules
- DV: UVM-based, Python scripts for flow orchestration
- Comments: English
- Build: Make + Python hybrid, FuseSoC for IP management
- Vendor management: `.vendor.hjson` + `.lock.hjson` files

## Local Environment Setup & Patches

### Spike Cosim Fork

Ibex requires the **lowRISC fork** of Spike, NOT the upstream `riscv-software-src/riscv-isa-sim`:

- Repository: `https://github.com/lowRISC/riscv-isa-sim`, branch `ibex_cosim`
- Pre-built package: `https://storage.googleapis.com/ibex-cosim-builds/ibex-cosim-6d5b660.tar.gz`
- Local install: `/home/u1/software/toolchain/riscv-isa-sim/riscv-isa-sim/`
- PKG_CONFIG_PATH: `/home/u1/software/toolchain/riscv-isa-sim/riscv-isa-sim/lib/pkgconfig`

The upstream Spike is missing Ibex-specific extensions (NMI, icache scramble key, custom processor APIs). Using upstream Spike causes compilation errors in `dv/cosim/spike_cosim.cc` (`get_cfg()`, `get_harts()`, `nmi`, `set_ic_scr_key_valid` etc.).

### glibc Compatibility (CentOS 7)

The pre-built ibex-cosim package was compiled against glibc 2.32+ (`__libc_single_threaded`), but CentOS 7 ships glibc 2.17.

Fix applied:
- `dv/cosim/glibc_compat.c` — stub providing `char __libc_single_threaded = 0;`
- `dv/uvm/core_ibex/ibex_dv_cosim_dpi.f` — added `glibc_compat.c` to DPI-C file list

### GCC 15 `-march` Compatibility

GCC 12+ requires explicit `_zicsr_zifencei` in `-march` for CSR and fence instructions (previously implicit in `i` extension).

Files patched:
- `dv/uvm/core_ibex/scripts/ibex_cmd.py:116` — `toolchain_isa` appends `_zicsr_zifencei`
- `dv/uvm/core_ibex/riscv_dv_extension/testlist.yaml` — hardcoded `-march=rv32im` → `rv32im_zicsr_zifencei`
- `dv/uvm/core_ibex/directed_tests/directed_testlist.yaml` — `-march=rv32imc` → `rv32imc_zicsr_zifencei`
- `dv/uvm/core_ibex/directed_tests/gen_testlist.py` — same as above

### Running DV Tests

```bash
# 1. 设置 PKG_CONFIG_PATH 指向 ibex-cosim Spike
export PKG_CONFIG_PATH=/home/u1/software/toolchain/riscv-isa-sim/riscv-isa-sim/lib/pkgconfig

# 2. 运行仿真
make -C /home/u1/projects/ibex/dv/uvm/core_ibex \
     SIMULATOR=vcs ISS=spike IBEX_CONFIG=opentitan \
     TEST=riscv_arithmetic_basic_test SEED=1 ITERATIONS=1

make -C dv/uvm/core_ibex \
       SIMULATOR=vcs ISS=spike IBEX_CONFIG=opentitan \
       COV=1 SEED=1 -j64 -k
```

Key parameters:

| Parameter | Description | Values |
|-----------|-------------|--------|
| `SIMULATOR` | Must specify explicitly (default xlm unavailable) | `vcs` |
| `ISS` | Instruction set simulator | `spike` |
| `IBEX_CONFIG` | Hardware configuration | `opentitan`, `small`, `maxperf`, etc. |
| `TEST` | Test case name | See `testlist.yaml` (~50+ definitions) |
| `SEED` | Random seed | Any integer |
| `ITERATIONS` | Iteration count (default 10) | Use `1` for debugging |
| `GOAL` | Run only up to a specific stage (for debugging) | `core_config`, `instr_gen_build`, `instr_gen_run`, `rtl_tb_compile`, `rtl_sim_run` |
| `COV` | Enable coverage collection | `1` |
| `WAVES` | Enable waveform dumping | `1` |

### Tool Versions

| Tool | Version | Path |
|------|---------|------|
| VCS | T-2022.06 | `/home/synopsys/vcs/T-2022.06/` |
| RISC-V GCC | 15.1.0 (riscv64-unknown-elf) | `/home/u1/software/toolchain/riscv/` |
| Spike (upstream, NOT for cosim) | v1.1.1-dev | `/home/u1/software/toolchain/riscv/` |
| Spike (ibex-cosim fork) | ibex-cosim-6d5b660 | `/home/u1/software/toolchain/riscv-isa-sim/riscv-isa-sim/` |
| Python | 3.9 (miniconda3) | `/home/u1/software/miniconda3/` |
| FuseSoC | 2.4.3 | pip installed |
