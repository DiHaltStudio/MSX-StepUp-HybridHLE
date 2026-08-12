extends Node2D

@onready var cpu: Z80Node         = $Z80Node
@onready var tilemap: TileMapLayer = $TileMapLayer

# ── VDP TMS9918A ──────────────────────────────────────────────────────────────
const VRAM_SIZE   := 16384
const SCREEN_COLS := 32
const SCREEN_ROWS := 24

# ── Sprites ───────────────────────────────────────────────────────────────────
const SAT_BASE     := 0x1B00   # Sprite Attribute Table en VRAM
const SPRITE_COUNT := 32       # Máximo 32 planos MSX
const SPRITE_SIZE  := 64       # 64x64 píxeles (x4)
const SPRITE_COLS  := 16       # columnas en stepup_sprites.png

var sprite_nodes: Array = []
var sprite_container: Node2D
var logo_sprite: Sprite2D
var logo_static_tex: Texture2D
var logo_frames: Array = []
var logo_state: int = 0   # 0=IDLE 1=ANIM_FWD 2=WAIT_REV 3=ANIM_REV
var logo_counter: int = 0

const LOGO_WAIT_TICKS  := 60  # 1 segundo a 60 Hz
const LOGO_FRAME_TICKS := 6   # 10 fps (6 ticks por frame)
var anim_tick: int = 0        # contador global de animación (60 Hz)
var intro_active: bool = true
var intro_ticks:  int  = 0
var intro_sprite: Sprite2D
var intro_bg: ColorRect
const INTRO_DURATION := 240  # 4 segundos a 60 Hz
var last_phase_val: int = -1
var audio_players: Dictionary = {}
var last_ay: int = 0
var last_burp: int = 0
var last_jump: int = 0
var last_step: int = 0
var last_count: int = 0
var last_nextstage: int = 0
var last_startgame_state: bool = false
var last_gameover_state: bool = false
var ufo_cooldown: int = 0
var machine_ready: bool = false
var touch_input := {
	"left": false,
	"up": false,
	"down": false,
	"right": false,
	"action": false,
}
var touch_controls: CanvasLayer
var rom_setup: CanvasLayer
var rom_status: Label
var rom_dialog: FileDialog

# ── Machine image ──────────────────────────────────────────────────────────────
const CBIOS_PATH := "res://roms/cbios_main_msx1_eu.rom"
const INITIAL_RAM_PATH := "res://roms/initial_ram_8000.bin"
const USER_ROM_FILENAME := "stepup.rom"
const STEPUP_ROM_SIZE := 8192
const STEPUP_ACCEPTED_DUMP_SIZES := [8192, 16384, 32768]
const STEPUP_TESTED_SHA256 := "d62c19f7023841e1f74953df58626c350e8549861576749ab1e01a6f1214406a"
const STEPUP_HEADER := [0x41, 0x42, 0x22, 0x41]

# ── Keyboard Matrix (PPI) ─────────────────────────────────────────────────────
var keyboard_matrix: PackedByteArray = PackedByteArray()
var selected_row: int = 0

var vram            := PackedByteArray()
var vdp_addr        := 0
var vdp_latch_stage := 0
var vdp_latch_first := 0
var vdp_read_buffer := 0
var vdp_regs        := PackedByteArray()
var vdp_status      := 0

func _vdp_init() -> void:
	vram.resize(VRAM_SIZE)
	vram.fill(0)
	vdp_regs.resize(8)
	vdp_regs.fill(0)
	vdp_addr        = 0
	vdp_latch_stage = 0
	vdp_latch_first = 0
	vdp_read_buffer = 0
	vdp_status      = 0

	keyboard_matrix.resize(12)
	keyboard_matrix.fill(0xFF)
	selected_row = 0

func _vdp_reset_latch() -> void:
	vdp_latch_stage = 0
	vdp_latch_first = 0

func _vdp_prefetch() -> void:
	vdp_read_buffer = vram[vdp_addr & 0x3FFF]
	vdp_addr = (vdp_addr + 1) & 0x3FFF

func _vdp_data_write(value: int) -> void:
	vram[vdp_addr & 0x3FFF] = value & 0xFF
	vdp_addr = (vdp_addr + 1) & 0x3FFF
	vdp_read_buffer = value & 0xFF
	_vdp_reset_latch()

func _vdp_data_read() -> int:
	var data := vdp_read_buffer
	_vdp_prefetch()
	_vdp_reset_latch()
	return data

func _vdp_ctrl_write(value: int) -> void:
	value &= 0xFF
	if vdp_latch_stage == 0:
		vdp_latch_first = value
		vdp_latch_stage = 1
	else:
		vdp_latch_stage = 0
		if value & 0x80:
			vdp_regs[value & 0x07] = vdp_latch_first
		elif value & 0x40:
			vdp_addr = vdp_latch_first | ((value & 0x3F) << 8)
		else:
			vdp_addr = vdp_latch_first | ((value & 0x3F) << 8)
			_vdp_prefetch()
		vdp_latch_first = 0

func _vdp_status_read() -> int:
	var st := vdp_status
	vdp_status = 0
	_vdp_reset_latch()
	cpu.clear_int()
	return st

# ── Godot ─────────────────────────────────────────────────────────────────────

const MSX_W := SCREEN_COLS * 32  # 1024
const MSX_H := SCREEN_ROWS * 32  # 768

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 1

	_vdp_init()
	_init_intro()
	_init_sprites()
	_init_tile_shader()
	_init_sounds()
	_init_logo()
	_init_touch_controls()

	cpu.set_port_in_callback(Callable(self, "_on_port_in"))
	cpu.set_port_out_callback(Callable(self, "_on_port_out"))

	machine_ready = _load_machine_memory()
	if machine_ready:
		_set_initial_cpu_state()
	else:
		_show_rom_setup()

func _set_initial_cpu_state() -> void:
	cpu.set_registers({
		"AF":  0x0124, "AF2": 0x3420,
		"BC":  0x0001, "BC2": 0x04F3,
		"DE":  0x4122, "DE2": 0x550C,
		"HL":  0x4004, "HL2": 0x4122,
		"IX":  0x4122, "IY":  0x0124,
		"SP":  0xF08E,
		"I":   0x00,   "R":   0x04,
		"IFF1": 0,     "IFF2": 0,
		"IM":  1,
		"PC":  0x4122,
	})

func _load_machine_memory() -> bool:
	var rom_path := _find_user_rom()
	if rom_path.is_empty():
		print("Step Up ROM not found; waiting for the user to select it.")
		return false

	var cbios := _read_binary(CBIOS_PATH)
	var source_rom := _read_binary(rom_path)
	var rom := _normalize_stepup_rom(source_rom)
	var initial_ram := _read_binary(INITIAL_RAM_PATH)
	if cbios.size() != 32768:
		push_error("Invalid C-BIOS image: expected 32768 bytes, got %d" % cbios.size())
		return false
	if rom.size() != STEPUP_ROM_SIZE:
		push_error("Unsupported Step Up ROM layout: expected a recognizable 8, 16, or 32 KiB dump")
		return false
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(rom)
	var rom_hash: String = hash_context.finish().hex_encode()
	if rom_hash != STEPUP_TESTED_SHA256:
		print("Step Up ROM variant accepted but not yet verified (normalized SHA-256: %s)." % rom_hash)
	if initial_ram.size() != 32768:
		push_error("Invalid initial RAM image: expected 32768 bytes, got %d" % initial_ram.size())
		return false

	# Flat 64 KiB image visible to the Z80 at the captured game entry point:
	#   0000-3FFF  C-BIOS MSX1 EU
	#   4000-5FFF  user's 8 KiB Step Up cartridge
	#   6000-7FFF  cartridge mirror
	#   8000-FFFF  initial RAM snapshot
	var memory := PackedByteArray()
	memory.resize(65536)
	memory.fill(0xFF)
	for i in range(0x4000):
		memory[i] = cbios[i]
	for i in range(STEPUP_ROM_SIZE):
		memory[0x4000 + i] = rom[i]
		memory[0x6000 + i] = rom[i]
	for i in range(initial_ram.size()):
		memory[0x8000 + i] = initial_ram[i]
	cpu.set_memory(memory)
	return true

func _find_user_rom() -> String:
	var candidates: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			candidates.append(arg.trim_prefix("--rom="))
	if OS.has_feature("editor"):
		candidates.append(ProjectSettings.globalize_path("res://roms/%s" % USER_ROM_FILENAME))
	else:
		var executable_dir := OS.get_executable_path().get_base_dir()
		candidates.append(executable_dir.path_join("roms").path_join(USER_ROM_FILENAME))
		if OS.has_feature("macos"):
			# The executable lives in Game.app/Contents/MacOS. Also accept a roms
			# directory beside the .app bundle for a normal downloadable ZIP.
			var bundle_parent := executable_dir.get_base_dir().get_base_dir().get_base_dir()
			candidates.append(bundle_parent.path_join("roms").path_join(USER_ROM_FILENAME))
	candidates.append(ProjectSettings.globalize_path("user://roms/%s" % USER_ROM_FILENAME))
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""

func _read_binary(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open binary file: %s" % path)
		return PackedByteArray()
	return file.get_buffer(file.get_length())

func _normalize_stepup_rom(source: PackedByteArray) -> PackedByteArray:
	if source.size() not in STEPUP_ACCEPTED_DUMP_SIZES:
		return PackedByteArray()
	# Several catalogued dumps are padded or overdumped. Locate the 8 KiB bank
	# carrying the Step Up cartridge header and map that bank at 0x4000.
	for bank_offset in range(0, source.size(), STEPUP_ROM_SIZE):
		var header_matches := true
		for i in range(STEPUP_HEADER.size()):
			if source[bank_offset + i] != STEPUP_HEADER[i]:
				header_matches = false
				break
		if header_matches:
			return source.slice(bank_offset, bank_offset + STEPUP_ROM_SIZE)
	return PackedByteArray()

func _show_rom_setup() -> void:
	rom_setup = CanvasLayer.new()
	rom_setup.layer = 200
	add_child(rom_setup)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.035, 0.06, 0.96)
	rom_setup.add_child(shade)

	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310, -165)
	panel.size = Vector2(620, 330)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 18)
	rom_setup.add_child(panel)

	var title := Label.new()
	title.text = "MSX StepUp HybridHLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	panel.add_child(title)

	var explanation := Label.new()
	explanation.text = "The original Step Up cartridge is not included.\nSelect your legally obtained Step Up ROM dump to continue.\n8, 16, and 32 KiB catalogued dump layouts are accepted."
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size = Vector2(620, 100)
	explanation.add_theme_font_size_override("font_size", 20)
	panel.add_child(explanation)

	var choose := Button.new()
	choose.text = "Select Step Up ROM"
	choose.custom_minimum_size = Vector2(300, 56)
	choose.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choose.add_theme_font_size_override("font_size", 20)
	choose.pressed.connect(_open_rom_dialog)
	panel.add_child(choose)

	rom_status = Label.new()
	rom_status.text = "Expected: a recognizable 8, 16, or 32 KiB Step Up dump"
	rom_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rom_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rom_status.custom_minimum_size = Vector2(620, 52)
	panel.add_child(rom_status)

	rom_dialog = FileDialog.new()
	rom_dialog.access = FileDialog.ACCESS_FILESYSTEM
	rom_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	rom_dialog.use_native_dialog = true
	rom_dialog.title = "Select your original Step Up ROM"
	rom_dialog.add_filter("*.rom,*.ROM", "ROM images", "application/octet-stream")
	rom_dialog.file_selected.connect(_import_user_rom)
	rom_setup.add_child(rom_dialog)

func _open_rom_dialog() -> void:
	rom_dialog.popup_centered_ratio(0.8)

func _import_user_rom(source_path: String) -> void:
	var rom := _read_binary(source_path)
	var normalized_rom := _normalize_stepup_rom(rom)
	if normalized_rom.size() != STEPUP_ROM_SIZE:
		rom_status.text = "That file is not a recognized 8, 16, or 32 KiB Step Up dump."
		return
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(normalized_rom)
	var rom_hash := hash_context.finish().hex_encode()

	var rom_dir := ProjectSettings.globalize_path("user://roms")
	var dir_error := DirAccess.make_dir_recursive_absolute(rom_dir)
	if dir_error != OK:
		rom_status.text = "Could not create the private ROM directory (error %d)." % dir_error
		return
	var destination := rom_dir.path_join(USER_ROM_FILENAME)
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		rom_status.text = "Could not save the ROM (error %d)." % FileAccess.get_open_error()
		return
	# Store the normalized 8 KiB cartridge image, not any padding/overdump.
	output.store_buffer(normalized_rom)
	output.close()
	if rom_hash == STEPUP_TESTED_SHA256:
		rom_status.text = "Tested ROM accepted. Starting..."
	else:
		rom_status.text = "ROM variant accepted. Starting..."
	get_tree().reload_current_scene()

func _init_touch_controls() -> void:
	if not OS.has_feature("mobile"):
		return
	touch_controls = CanvasLayer.new()
	touch_controls.layer = 100
	add_child(touch_controls)

	_add_touch_button("LEFT", "left", Vector2(28, 630), Vector2(105, 105))
	_add_touch_button("UP", "up", Vector2(133, 525), Vector2(105, 105))
	_add_touch_button("DOWN", "down", Vector2(133, 630), Vector2(105, 105))
	_add_touch_button("RIGHT", "right", Vector2(238, 630), Vector2(105, 105))
	_add_touch_button("ACTION", "action", Vector2(825, 590), Vector2(155, 125))

func _add_touch_button(label: String, input_name: String, position: Vector2, size: Vector2) -> void:
	var button := Button.new()
	button.text = label
	button.position = position
	button.size = size
	button.modulate = Color(1, 1, 1, 0.58)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.button_down.connect(func(): touch_input[input_name] = true)
	button.button_up.connect(func(): touch_input[input_name] = false)
	touch_controls.add_child(button)

func _physics_process(_delta: float) -> void:
	if not machine_ready:
		return
	if intro_active:
		intro_ticks += 1
		if intro_ticks >= INTRO_DURATION or Input.is_key_pressed(KEY_SPACE) or touch_input.action:
			intro_active = false
			intro_sprite.queue_free()
			intro_bg.queue_free()
			tilemap.visible = true
		return

	anim_tick += 1
	if anim_tick == 60:
		sprite_container.visible = true
	vdp_status |= 0x9F
	cpu.trigger_int(0xFF)
	_update_keyboard_matrix()
	cpu.execute_cycles(71591)
	_poll_phase_change()
	_poll_sounds()
	_inject_credits()
	_render_tilemap()
	_render_sprites()
	_update_logo_visibility()

func _on_port_in(port: int) -> int:
	match port:
		0x98: return _vdp_data_read()
		0x99: return _vdp_status_read()
		0xA9: return keyboard_matrix[selected_row] if selected_row < 12 else 0xFF
	return 0xFF

func _on_port_out(port: int, value: int) -> void:
	match port:
		0x98: _vdp_data_write(value)
		0x99: _vdp_ctrl_write(value)
		0xAA: selected_row = value & 0x0F

# ── Render ────────────────────────────────────────────────────────────────────

func _init_intro() -> void:
	intro_bg = ColorRect.new()
	intro_bg.color = Color(0, 0, 0, 1)
	intro_bg.size = Vector2(1024, 768)
	intro_bg.z_index = 99
	add_child(intro_bg)

	intro_sprite = Sprite2D.new()
	intro_sprite.texture = load("res://assets/graphics/intro.png")
	intro_sprite.centered = true
	intro_sprite.position = Vector2(512, 384)
	intro_sprite.z_index = 100
	add_child(intro_sprite)

	# Ocultar juego durante intro
	tilemap.visible = false

func _init_sprites() -> void:
	sprite_container = Node2D.new()
	sprite_container.z_index = 1
	sprite_container.visible = false
	add_child(sprite_container)
	var tex: Texture2D = load("res://assets/graphics/stepup_sprites.png")
	for i in range(SPRITE_COUNT):
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.region_enabled = true
		sp.region_rect = Rect2(0, 0, SPRITE_SIZE, SPRITE_SIZE)
		sp.centered = false
		sp.z_index = SPRITE_COUNT - i  # plano 0 encima de todos
		sprite_container.add_child(sp)
		sprite_nodes.append(sp)

func _init_logo() -> void:
	logo_static_tex = load("res://assets/graphics/stepup_logo.png")
	for i in range(10):
		logo_frames.append(load("res://assets/graphics/logo_frames/frame_%02d.png" % i))

	logo_sprite = Sprite2D.new()
	logo_sprite.texture = logo_static_tex
	logo_sprite.centered = false
	logo_sprite.position = Vector2(288, 192)
	logo_sprite.z_index = SPRITE_COUNT + 1
	logo_sprite.visible = false
	add_child(logo_sprite)

func _update_logo_visibility() -> void:
	var cond := (vram[0x18c9] == 172 and vram[0x18e9] == 173)
	if not cond:
		if logo_sprite.visible:
			logo_sprite.visible = false
			logo_state   = 0
			logo_counter = 0
		return

	logo_sprite.visible = true
	logo_counter += 1

	match logo_state:
		0:  # IDLE — muestra estático, espera 1s
			logo_sprite.texture = logo_static_tex
			if logo_counter >= LOGO_WAIT_TICKS:
				logo_state   = 1
				logo_counter = 0
		1:  # ANIM_FWD
			var fi := logo_counter / LOGO_FRAME_TICKS
			if fi >= logo_frames.size():
				logo_state   = 2
				logo_counter = 0
			else:
				logo_sprite.texture = logo_frames[fi]
		2:  # WAIT_REV — mantiene último frame, espera 1s
			logo_sprite.texture = logo_frames[logo_frames.size() - 1]
			if logo_counter >= LOGO_WAIT_TICKS:
				logo_state   = 3
				logo_counter = 0
		3:  # ANIM_REV
			var fi := (logo_frames.size() - 1) - (logo_counter / LOGO_FRAME_TICKS)
			if fi < 0:
				logo_state   = 0
				logo_counter = 0
				logo_sprite.texture = logo_static_tex
			else:
				logo_sprite.texture = logo_frames[fi]

func _render_sprites() -> void:
	for plane in range(SPRITE_COUNT):
		var base  := SAT_BASE + plane * 4
		var y_raw := vram[base + 0]
		var x_pos := vram[base + 1]
		var pat   := vram[base + 2]
		var attr  := vram[base + 3]
		var sp: Sprite2D = sprite_nodes[plane]

		# 0xD0 = fin de lista de sprites activos
		if y_raw == 0xD0:
			sp.visible = false
			continue

		# Lógica de tinte para el plano 12 (especificado por el usuario)
		if plane == 12:
			var color_bits := attr & 0x0F
			if color_bits != 0x0E:
				sp.modulate = Color(1.8, 0.6, 0.6)
			else:
				sp.modulate = Color(1, 1, 1)

		# TMS9918A: el sprite aparece en Y+1
		var screen_y := (y_raw + 1) & 0xFF

		var sprite_idx := pat / 4
		# Animación de fuego: sprites 23↔39 y 24↔40, alternando cada 30 ticks (0.5s)
		if sprite_idx == 23 and (anim_tick / 30) % 2 == 1:
			sprite_idx = 39
		elif sprite_idx == 24 and (anim_tick / 30) % 2 == 1:
			sprite_idx = 40
		var atlas_col  := sprite_idx % SPRITE_COLS
		var atlas_row  := sprite_idx / SPRITE_COLS

		sp.region_rect = Rect2(
			atlas_col * SPRITE_SIZE,
			atlas_row * SPRITE_SIZE,
			SPRITE_SIZE,
			SPRITE_SIZE
		)
		sp.position = Vector2(x_pos * 4, screen_y * 4)
		sp.visible  = true

const CREDITS_TEXT := "DiHalt"
const CREDITS_ADDR := 0x1a69-5

func _inject_credits() -> void:
	if vram[0x1a34] != 0x62 or vram[0x1a35] != 0x79:
		return
	for i in range(CREDITS_TEXT.length()):
		vram[CREDITS_ADDR + i] = CREDITS_TEXT.unicode_at(i)

func _render_tilemap() -> void:
	# TMS9918A name table fija en 0x1800 (32x24 tiles)
	# Cada byte es un tile ID: ID 0 → atlas (0,0), ID 1 → (1,0), ID 16 → (0,1) …
	for row in range(SCREEN_ROWS):
		for col in range(SCREEN_COLS):
			var tile_id: int = vram[0x1800 + row * SCREEN_COLS + col]
			tilemap.set_cell(
				Vector2i(col, row),
				0,
				Vector2i(tile_id & 0x0F, tile_id >> 4)
			)

func _update_keyboard_matrix() -> void:
	# MSX Keyboard Matrix Row 8 (Cursors & Space)
	# Logic: 0 = pressed, 1 = released
	var row8: int = 0xFF

	if Input.is_key_pressed(KEY_SPACE) or touch_input.action: row8 &= ~(1 << 0)
	if Input.is_key_pressed(KEY_LEFT) or touch_input.left:    row8 &= ~(1 << 4)
	if Input.is_key_pressed(KEY_UP) or touch_input.up:        row8 &= ~(1 << 5)
	if Input.is_key_pressed(KEY_DOWN) or touch_input.down:    row8 &= ~(1 << 6)
	if Input.is_key_pressed(KEY_RIGHT) or touch_input.right:  row8 &= ~(1 << 7)

	keyboard_matrix[8] = row8

func _init_tile_shader() -> void:
	var shader := load("res://scenes/msx_godot_engine/tile_tint.gdshader")
	var mat    := ShaderMaterial.new()
	mat.shader = shader
	tilemap.material = mat

func _poll_phase_change() -> void:
	# Consultar RAM 0xE600 (fase - 1)
	var current_phase := cpu.mem_read(0xE600)
	if current_phase != last_phase_val:
		last_phase_val = current_phase

		# Limpiar líneas 19 y 20 en VRAM (32 * 2 = 64 bytes)
		# Tabla de nombres fija en 0x1800. Fila 19 empieza en 19 * 32 = 608 (0x260)
		var vram_row_start := 0x1800 + 19 * 32
		for i in range(64):
			vram[vram_row_start + i] = 0

		# Condición: fases 2, 3, 6, 7, 10, 11... (fase % 4 >= 2)
		var purple_enabled := (current_phase % 4) >= 2
		if tilemap.material is ShaderMaterial:
			tilemap.material.set_shader_parameter("purple_enabled", purple_enabled)

func _are_phase_lines_blank() -> bool:
	var vram_row_start := 0x1800 + 19 * 32
	for i in range(64):
		if vram[vram_row_start + i] != 0:
			return false
	return true

func _init_sounds() -> void:
	for sname in ["ay", "burp", "jump", "startgame", "gameover", "ufo", "step", "count", "nhe", "nextstage"]:
		var asp := AudioStreamPlayer.new()
		var stream = load("res://assets/audio/%s.wav" % sname)
		if stream:
			asp.stream = stream
			add_child(asp)
			audio_players[sname] = asp
		else:
			push_error("Could not load sound: res://assets/audio/%s.wav" % sname)

func _play_sound(sname: String) -> void:
	if audio_players.has(sname):
		audio_players[sname].play()

func _poll_sounds() -> void:
	# ay -> 0xE41C
	var v_ay = cpu.mem_read(0xE41C)
	if v_ay != 0 and last_ay == 0:
		_play_sound("ay")
	last_ay = v_ay

	# burp -> 0xE41D
	var v_burp = cpu.mem_read(0xE41D)
	if v_burp != 0 and last_burp == 0:
		_play_sound("burp")
	last_burp = v_burp

	# jump -> 0xE4F0
	var v_jump = cpu.mem_read(0xE4F0)
	if v_jump != 0 and last_jump == 0:
		_play_sound("jump")
	last_jump = v_jump

	# startgame -> vram 0x1972==0x21, 0x1aa9==0x30, 0x1aaa==0x31
	# Added: 0x1826==0x00, 0x1827==0x30, 0x1828==0x30, 0x1abc==0xd0
	var cond_start = (vram[0x1972] == 0x21 and vram[0x1aa9] == 0x30 and vram[0x1aaa] == 0x31 and
					  vram[0x1826] == 0x00 and vram[0x1827] == 0x30 and vram[0x1828] == 0x30 and
					  vram[0x1abc] == 0xd0)
	if cond_start and not last_startgame_state:
		_play_sound("startgame")
	last_startgame_state = cond_start

	# gameover -> vram 0x1974==0x21
	var cond_gameover = (vram[0x1974] == 0x21)
	if cond_gameover and not last_gameover_state:
		_play_sound("gameover")
	last_gameover_state = cond_gameover

	# step + count comparten la misma dirección 0xE01E
	var v_e01e = cpu.mem_read(0xE01E)
	if v_e01e == 0x07 and last_step == 0x06:   # step: 0x06 -> 0x07
		_play_sound("step")
	if v_e01e == 0x00 and last_count == 0x05:  # count/nhe: 0x05 -> 0x00
		if _are_phase_lines_blank():
			_play_sound("count")
		else:
			_play_sound("nhe")
	last_step  = v_e01e
	last_count = v_e01e

	# TODO: This one doesn't work !!!!!!!!!!!!! ********************************
	# nextstage -> vram 0x1aaa cambia entre valores 0x30-0x39
	var v_nextstage := vram[0x1aaa]
	if v_nextstage != last_nextstage and v_nextstage >= 0x30 and v_nextstage <= 0x39 and last_nextstage >= 0x30 and last_nextstage <= 0x39:
		_play_sound("nextstage")
	last_nextstage = v_nextstage

	# ufo -> any sprite pattern == 0x54, cooldown 60 frames
	if ufo_cooldown > 0:
		ufo_cooldown -= 1

	if ufo_cooldown <= 0:
		var ufo_found := false
		for i in range(SPRITE_COUNT):
			var base := SAT_BASE + i * 4
			# Condition: pattern 0x54 and Y coordinate != 0xD1 (hidden)
			if vram[base + 2] == 0x54 and vram[base + 0] != 0xD1:
				ufo_found = true
				break
		if ufo_found:
			_play_sound("ufo")
			ufo_cooldown = 60
