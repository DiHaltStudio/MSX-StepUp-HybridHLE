// z80_node.cpp — Z80 GDExtension wrapper
// Fixed version using correct field names from floooh/chips z80.h

// Define CHIPS_IMPL here (and only here) so z80.h compiles its implementation
// in exactly one translation unit.
#define CHIPS_IMPL
#include "z80_node.hpp"
#include <cstdio>
#include <cstring>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

Z80Node::Z80Node() {
  memset(_ram, 0, sizeof(_ram));
  memset(_ports_in, 0, sizeof(_ports_in));
  memset(_ports_out, 0, sizeof(_ports_out));
  _int_pending = false;
  _nmi_pending = false;
  _int_data = 0xFF;

  z80_init(&_cpu);
  _pins = z80_prefetch(&_cpu, 0x0000); // Start at address 0
}

Z80Node::~Z80Node() {}

// ─── Bus handling (tick loop) ──────────────────────────────────────────────

void Z80Node::_handle_bus() {
  // Memory access
  if (_pins & Z80_MREQ) {
    const uint16_t addr = Z80_GET_ADDR(_pins);
    if (_pins & Z80_RD) {
      Z80_SET_DATA(_pins, _ram[addr]);
    } else if (_pins & Z80_WR) {
      uint8_t data = Z80_GET_DATA(_pins);
      _ram[addr] = data;
      if (_mem_write_callback.is_valid()) {
        _mem_write_callback.call((int)addr, (int)data);
      }
    }
  }
  // I/O access
  else if (_pins & Z80_IORQ) {
    if (_pins & Z80_M1) {
      // Interrupt acknowledge — the Z80 acknowledges the IRQ but /INT remains
      // active until the peripheral (VDP) releases it (via clear_int() from
      // GDScript)
      Z80_SET_DATA(_pins, _int_data);
    } else {
      const uint16_t port = Z80_GET_ADDR(_pins) & 0xFF;
      if (_pins & Z80_RD) {
        if (_port_in_callback.is_valid()) {
          Variant ret = _port_in_callback.call(port);
          Z80_SET_DATA(_pins, static_cast<uint8_t>((int)ret));
        } else {
          Z80_SET_DATA(_pins, _ports_in[port]);
        }
      } else if (_pins & Z80_WR) {
        uint8_t data = Z80_GET_DATA(_pins);
        _ports_out[port] = data;
        if (_port_out_callback.is_valid()) {
          _port_out_callback.call(port, data);
        }
      }
    }
  }

  // Interrupt signals (pins are active while high)
  if (_nmi_pending) {
    _pins |= Z80_NMI;
    _nmi_pending = false;
  }
  if (_int_pending) {
    _pins |= Z80_INT;
  } else {
    _pins &= ~Z80_INT;
  }
}

// ─── Memory ─────────────────────────────────────────────────────────────────

PackedByteArray Z80Node::get_memory() const {
  PackedByteArray out;
  out.resize(RAM_SIZE);
  memcpy(out.ptrw(), _ram, RAM_SIZE);
  return out;
}

void Z80Node::set_memory(const PackedByteArray &data) {
  int len = data.size();
  if (len > RAM_SIZE)
    len = RAM_SIZE;
  memcpy(_ram, data.ptr(), len);
}

int Z80Node::mem_read(int addr) const {
  if (addr < 0 || addr >= RAM_SIZE)
    return 0;
  return _ram[addr];
}

void Z80Node::mem_write(int addr, int val) {
  if (addr < 0 || addr >= RAM_SIZE)
    return;
  _ram[addr] = static_cast<uint8_t>(val);
}

void Z80Node::load_binary(const PackedByteArray &data, int base_addr) {
  if (base_addr < 0 || base_addr >= (int)sizeof(_ram))
    return;
  int len = data.size();
  if (base_addr + len > (int)sizeof(_ram))
    len = (int)sizeof(_ram) - base_addr;
  memcpy(_ram + base_addr, data.ptr(), len);
}

// ─── Execution ───────────────────────────────────────────────────────────────

int Z80Node::execute_cycles(int n) {
  int cycles_done = 0;
  while (cycles_done < n) {
    _pins = z80_tick(&_cpu, _pins);
    _handle_bus();
    cycles_done++;
  }
  return cycles_done;
}

int Z80Node::execute_cycles_with_breakpoints(
    int n, const PackedInt32Array &breakpoints) {
  int cycles_done = 0;
  int bp_count = breakpoints.size();

  // printf("[Z80] Executing %d cycles with %d breakpoints\n", n, bp_count);
  for (int i = 0; i < bp_count; i++) {
    printf("      - BP[%d]: 0x%04X\n", i, (int)breakpoints[i]);
  }

  while (cycles_done < n) {
    _pins = z80_tick(&_cpu, _pins);
    _handle_bus();
    cycles_done++;

    // M1 + RD is the stable moment for OPCODE FETCH capture
    if ((_pins & Z80_M1) && (_pins & Z80_RD)) {
      uint16_t current_pc = Z80_GET_ADDR(_pins);

      printf("PC: 0x%04X\n", current_pc);

      for (int i = 0; i < bp_count; i++) {
        if ((uint16_t)breakpoints[i] == current_pc) {
          printf("[Z80] BREAKPOINT REACHED at 0x%04X!\n", current_pc);
          return -1;
        }
      }
    }
  }
  return cycles_done;
}

int Z80Node::execute_instruction() {
  // Executes T-states until z80_opdone() confirms completion.
  // Safety limit: no Z80 instruction exceeds 23 T-states.
  int cycles_done = 0;
  do {
    _pins = z80_tick(&_cpu, _pins);
    _handle_bus();
    cycles_done++;
  } while (!z80_opdone(&_cpu) && cycles_done < 23);
  return cycles_done;
}

int Z80Node::execute_until_pc(int target_pc, int max_instrs) {
  // Executes instructions until reaching target_pc or max_instrs.
  // Used for step-over: target_pc = current_PC + length_of_current_instruction.
  int instrs = 0;
  while (instrs < max_instrs) {
    // one complete instruction
    int safety = 0;
    do {
      _pins = z80_tick(&_cpu, _pins);
      _handle_bus();
      safety++;
    } while (!z80_opdone(&_cpu) && safety < 23);
    instrs++;
    if ((int)(Z80_GET_ADDR(_pins) & 0xFFFF) == target_pc)
      break;
  }
  return instrs;
}

void Z80Node::reset() { _pins = z80_reset(&_cpu); }

int Z80Node::get_instr_pc() const {
  // After execute_instruction() or set_pc(), pins are in M1/T2:
  // the address bus contains the actual opcode address.
  return static_cast<int>(Z80_GET_ADDR(_pins) & 0xFFFF);
}

// ─── Interrupts ─────────────────────────────────────────────────────────────

void Z80Node::trigger_int(int bus_data) {
  _int_data = static_cast<uint8_t>(bus_data & 0xFF);
  _int_pending = true;
}

void Z80Node::trigger_nmi() { _nmi_pending = true; }

void Z80Node::clear_int() { _int_pending = false; }

// ─── Registers ───────────────────────────────────────────────────────────────

Dictionary Z80Node::get_registers() const {
  Dictionary d;
  d["PC"] = (int)_cpu.pc;
  d["SP"] = (int)_cpu.sp;
  d["AF"] = (int)_cpu.af;
  d["BC"] = (int)_cpu.bc;
  d["DE"] = (int)_cpu.de;
  d["HL"] = (int)_cpu.hl;
  d["IX"] = (int)_cpu.ix;
  d["IY"] = (int)_cpu.iy;
  d["AF2"] = (int)_cpu.af2;
  d["BC2"] = (int)_cpu.bc2;
  d["DE2"] = (int)_cpu.de2;
  d["HL2"] = (int)_cpu.hl2;
  d["I"] = (int)_cpu.ir >> 8;
  d["R"] = (int)_cpu.ir & 0xFF;
  d["IFF1"] = (int)_cpu.iff1;
  d["IFF2"] = (int)_cpu.iff2;
  d["IM"] = (int)_cpu.im;
  return d;
}

void Z80Node::set_registers(const Dictionary &regs) {
  if (regs.has("AF"))
    _cpu.af = (uint16_t)(int)regs["AF"];
  if (regs.has("BC"))
    _cpu.bc = (uint16_t)(int)regs["BC"];
  if (regs.has("DE"))
    _cpu.de = (uint16_t)(int)regs["DE"];
  if (regs.has("HL"))
    _cpu.hl = (uint16_t)(int)regs["HL"];
  if (regs.has("IX"))
    _cpu.ix = (uint16_t)(int)regs["IX"];
  if (regs.has("IY"))
    _cpu.iy = (uint16_t)(int)regs["IY"];
  if (regs.has("SP"))
    _cpu.sp = (uint16_t)(int)regs["SP"];
  if (regs.has("AF2"))
    _cpu.af2 = (uint16_t)(int)regs["AF2"];
  if (regs.has("BC2"))
    _cpu.bc2 = (uint16_t)(int)regs["BC2"];
  if (regs.has("DE2"))
    _cpu.de2 = (uint16_t)(int)regs["DE2"];
  if (regs.has("HL2"))
    _cpu.hl2 = (uint16_t)(int)regs["HL2"];
  if (regs.has("I") || regs.has("R")) {
    uint8_t i =
        regs.has("I") ? (uint8_t)(int)regs["I"] : (uint8_t)(_cpu.ir >> 8);
    uint8_t r =
        regs.has("R") ? (uint8_t)(int)regs["R"] : (uint8_t)(_cpu.ir & 0xFF);
    _cpu.ir = ((uint16_t)i << 8) | r;
  }
  if (regs.has("IFF1"))
    _cpu.iff1 = (uint8_t)(int)regs["IFF1"];
  if (regs.has("IFF2"))
    _cpu.iff2 = (uint8_t)(int)regs["IFF2"];
  if (regs.has("IM"))
    _cpu.im = (uint8_t)(int)regs["IM"];
  // PC is applied last via prefetch to update pins correctly
  if (regs.has("PC"))
    _pins = z80_prefetch(&_cpu, (uint16_t)(int)regs["PC"]);
}

void Z80Node::set_pc(int addr) {
  _pins = z80_prefetch(&_cpu, static_cast<uint16_t>(addr));
}

// ─── Ports ───────────────────────────────────────────────────────────────────

void Z80Node::set_port_in(int port, int value) {
  if (port < 0 || port >= PORT_SIZE)
    return;
  _ports_in[port] = static_cast<uint8_t>(value & 0xFF);
}

int Z80Node::get_port_out(int port) const {
  if (port < 0 || port >= PORT_SIZE)
    return 0;
  return _ports_out[port];
}

PackedByteArray Z80Node::get_ports_out() const {
  PackedByteArray out;
  out.resize(PORT_SIZE);
  memcpy(out.ptrw(), _ports_out, PORT_SIZE);
  return out;
}

PackedByteArray Z80Node::get_ports_in() const {
  PackedByteArray out;
  out.resize(PORT_SIZE);
  memcpy(out.ptrw(), _ports_in, PORT_SIZE);
  return out;
}

// ─── Callbacks ───────────────────────────────────────────────────────────────

void Z80Node::set_port_in_callback(const Callable &cb) {
  _port_in_callback = cb;
}

void Z80Node::set_port_out_callback(const Callable &cb) {
  _port_out_callback = cb;
}

void Z80Node::set_mem_write_callback(const Callable &cb) {
  _mem_write_callback = cb;
}

// ─── Bind methods ────────────────────────────────────────────────────────────

void Z80Node::_bind_methods() {
  ClassDB::bind_method(D_METHOD("set_port_in_callback", "callback"),
                       &Z80Node::set_port_in_callback);
  ClassDB::bind_method(D_METHOD("set_port_out_callback", "callback"),
                       &Z80Node::set_port_out_callback);
  ClassDB::bind_method(D_METHOD("set_mem_write_callback", "callback"),
                       &Z80Node::set_mem_write_callback);
  ClassDB::bind_method(D_METHOD("get_memory"), &Z80Node::get_memory);
  ClassDB::bind_method(D_METHOD("set_memory", "data"), &Z80Node::set_memory);
  ClassDB::bind_method(D_METHOD("mem_read", "addr"), &Z80Node::mem_read);
  ClassDB::bind_method(D_METHOD("mem_write", "addr", "val"),
                       &Z80Node::mem_write);
  ClassDB::bind_method(D_METHOD("load_binary", "data", "base_addr"),
                       &Z80Node::load_binary);

  ClassDB::bind_method(D_METHOD("execute_cycles", "n"),
                       &Z80Node::execute_cycles);
  ClassDB::bind_method(
      D_METHOD("execute_cycles_with_breakpoints", "n", "breakpoints"),
      &Z80Node::execute_cycles_with_breakpoints);
  ClassDB::bind_method(D_METHOD("execute_instruction"),
                       &Z80Node::execute_instruction);
  ClassDB::bind_method(D_METHOD("execute_until_pc", "target_pc", "max_instrs"),
                       &Z80Node::execute_until_pc);
  ClassDB::bind_method(D_METHOD("get_instr_pc"), &Z80Node::get_instr_pc);
  ClassDB::bind_method(D_METHOD("reset"), &Z80Node::reset);

  ClassDB::bind_method(D_METHOD("trigger_int", "bus_data"),
                       &Z80Node::trigger_int);
  ClassDB::bind_method(D_METHOD("trigger_nmi"), &Z80Node::trigger_nmi);
  ClassDB::bind_method(D_METHOD("clear_int"), &Z80Node::clear_int);

  ClassDB::bind_method(D_METHOD("get_registers"), &Z80Node::get_registers);
  ClassDB::bind_method(D_METHOD("set_registers", "regs"),
                       &Z80Node::set_registers);
  ClassDB::bind_method(D_METHOD("set_pc", "addr"), &Z80Node::set_pc);

  ClassDB::bind_method(D_METHOD("set_port_in", "port", "value"),
                       &Z80Node::set_port_in);
  ClassDB::bind_method(D_METHOD("get_port_out", "port"),
                       &Z80Node::get_port_out);
  ClassDB::bind_method(D_METHOD("get_ports_out"), &Z80Node::get_ports_out);
  ClassDB::bind_method(D_METHOD("get_ports_in"), &Z80Node::get_ports_in);
}
