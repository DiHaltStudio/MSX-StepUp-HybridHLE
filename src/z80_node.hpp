#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>

// z80.h from floooh/chips — tick-based, single-header C
// CHIPS_IMPL must be defined in exactly ONE .cpp file before including this
// header.
extern "C" {
#include "../thirdparty/chips/z80.h"
}

namespace godot {

// Z80Node — exposes a complete Z80 CPU emulator to GDScript.
//
// Memory model: 64 KB internal uint8_t array, accessible from GDScript
//               as PackedByteArray.
// Execution: tick-based loop (z80_tick per clock cycle).
// Interrupts: trigger_int / trigger_nmi inject pins on the next tick.
// I/O ports : 256-byte in/out arrays updated each tick.

class Z80Node : public Node {
  GDCLASS(Z80Node, Node)

public:
  static const int RAM_SIZE = 65536;
  static const int PORT_SIZE = 256;

  Z80Node();
  ~Z80Node();

  // ── Memory ──────────────────────────────────────────────────────────────
  /// Returns a full 65536-byte copy of current RAM.
  PackedByteArray get_memory() const;
  /// Replaces the entire 64 KB RAM with data (must be ≤ 65536 bytes).
  void set_memory(const PackedByteArray &data);
  /// Reads one byte (0–255) from RAM at addr.
  int mem_read(int addr) const;
  /// Writes one byte val to RAM at addr. Does not fire mem_write_callback.
  void mem_write(int addr, int val);
  /// Copies data into RAM starting at base_addr. Clamps to 64 KB boundary.
  void load_binary(const PackedByteArray &data, int base_addr);

  // ── Execution ───────────────────────────────────────────────────────────
  /// Runs the CPU for n T-states. Returns actual T-states executed.
  /// For MSX at 50 Hz: pass 71591.
  int execute_cycles(int n);
  /// Like execute_cycles but stops early (returns -1) if PC hits a breakpoint.
  int execute_cycles_with_breakpoints(int n,
                                      const PackedInt32Array &breakpoints);
  /// Executes exactly one complete instruction. Returns T-states consumed.
  int execute_instruction();
  /// Runs instructions until PC == target_pc or max_instrs limit is reached.
  /// Use for step-over: target_pc = current_pc + instruction_length.
  int execute_until_pc(int target_pc, int max_instrs);
  /// Hardware reset: clears PC, SP, interrupt state and pins. RAM is preserved.
  void reset();
  /// Returns the address on the bus during the current M1/T2 cycle.
  /// Use this (not get_registers()["PC"]) for disassembly and debug display.
  int get_instr_pc() const;

  // ── Interrupts ──────────────────────────────────────────────────────────
  /// Asserts /INT. bus_data is placed on the data bus during IORQ+M1 ack.
  /// Use 0xFF for MSX IM1 mode. Pin stays high until clear_int() is called.
  void trigger_int(int bus_data);
  /// Asserts /NMI. CPU jumps to 0x0066 regardless of IFF1.
  void trigger_nmi();
  /// De-asserts /INT. Call from the port-in callback when the peripheral
  /// releases the interrupt line (e.g. after reading VDP status port 0x99).
  void clear_int();

  // ── Registers (debug) ───────────────────────────────────────────────────
  /// Returns all CPU registers as a Dictionary (PC, SP, AF, BC, DE, HL,
  /// IX, IY, AF2, BC2, DE2, HL2, I, R, IFF1, IFF2, IM).
  Dictionary get_registers() const;
  /// Sets any subset of registers from regs. Missing keys are left unchanged.
  /// PC is applied last via z80_prefetch() to update pin state correctly.
  void set_registers(const Dictionary &regs);
  /// Sets PC via z80_prefetch(). Equivalent to set_registers({"PC": addr}).
  void set_pc(int addr);

  // ── I/O Ports ───────────────────────────────────────────────────────────
  /// Sets the static input value for port (used when no port-in callback is set).
  void set_port_in(int port, int value);
  /// Returns the last value written by the CPU to port via OUT.
  int get_port_out(int port) const;
  /// Returns all 256 output port values as a PackedByteArray.
  PackedByteArray get_ports_out() const;
  /// Returns all 256 input port values as a PackedByteArray.
  PackedByteArray get_ports_in() const;

  // ── Callbacks ───────────────────────────────────────────────────────────
  /// Registers a callback invoked on every IN instruction.
  /// Signature: func(port: int) -> int  (return value → data bus).
  void set_port_in_callback(const Callable &cb);
  /// Registers a callback invoked on every OUT instruction.
  /// Signature: func(port: int, value: int) -> void
  void set_port_out_callback(const Callable &cb);
  /// Registers a callback invoked after every CPU memory write (MREQ+WR).
  /// The write to internal RAM has already been applied when this fires.
  /// Use it to implement memory mappers (e.g. Konami4 MegaROM bankswitching).
  /// Signature: func(addr: int, value: int) -> void
  void set_mem_write_callback(const Callable &cb);

protected:
  static void _bind_methods();

private:
  Callable _port_in_callback;
  Callable _port_out_callback;
  Callable _mem_write_callback;
  z80_t _cpu;
  uint64_t _pins; // current pin state (returned by z80_tick / z80_init)

  uint8_t _ram[RAM_SIZE];
  uint8_t _ports_in[PORT_SIZE];
  uint8_t _ports_out[PORT_SIZE];

  bool _int_pending;
  uint8_t _int_data;
  bool _nmi_pending;

  // Process one tick of the bus (called inside execute_cycles loop)
  void _handle_bus();
};

} // namespace godot
