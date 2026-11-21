extends Control
class_name GameHUD
## Compact gameplay HUD: mode badge, speedometer, rifle stance, and contextual interact prompt.

enum HudMode {
	ON_FOOT,
	DRIVING,
	FLYOVER,
	LEGACY_WALKER,
}

enum PromptTone {
	NONE,
	NORMAL,
	WARNING,
	BLOCKED,
}

@onready var status_panel: PanelContainer = $TopRightPanel
@onready var mode_label: Label = $TopRightPanel/Margin/VBox/ModeRow/ModeLabel
@onready var speed_label: Label = $TopRightPanel/Margin/VBox/SpeedLabel
@onready var stance_label: Label = $TopRightPanel/Margin/VBox/StanceLabel
@onready var prompt_panel: PanelContainer = $BottomPromptAnchor/PromptPanel
@onready var prompt_label: Label = $BottomPromptAnchor/PromptPanel/Margin/PromptLabel

var _normal_prompt_style: StyleBoxFlat
var _warning_prompt_style: StyleBoxFlat
var _blocked_prompt_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	set_mode(HudMode.ON_FOOT)
	set_rifle_stance(false)
	set_prompt("", PromptTone.NONE)


func _build_styles() -> void:
	_normal_prompt_style = StyleBoxFlat.new()
	_normal_prompt_style.bg_color = Color(0.06, 0.09, 0.11, 0.82)
	_normal_prompt_style.border_color = Color(0.55, 0.82, 0.98, 0.65)
	_normal_prompt_style.set_border_width_all(2)
	_normal_prompt_style.set_corner_radius_all(8)

	_warning_prompt_style = _normal_prompt_style.duplicate()
	_warning_prompt_style.border_color = Color(0.95, 0.72, 0.24, 0.8)

	_blocked_prompt_style = _normal_prompt_style.duplicate()
	_blocked_prompt_style.border_color = Color(0.92, 0.32, 0.30, 0.85)


func set_mode(mode: HudMode) -> void:
	if not is_node_ready():
		return
	match mode:
		HudMode.ON_FOOT:
			status_panel.visible = true
			mode_label.text = "ON FOOT"
			mode_label.modulate = Color(0.75, 0.94, 1.0, 1.0)
			speed_label.visible = false
			stance_label.visible = true
		HudMode.DRIVING:
			status_panel.visible = true
			mode_label.text = "DRIVING"
			mode_label.modulate = Color(0.98, 0.82, 0.42, 1.0)
			speed_label.visible = true
			stance_label.visible = false
		HudMode.FLYOVER:
			status_panel.visible = true
			mode_label.text = "FLYOVER"
			mode_label.modulate = Color(0.78, 0.86, 0.90, 1.0)
			speed_label.visible = false
			stance_label.visible = false
		HudMode.LEGACY_WALKER:
			status_panel.visible = false
			set_prompt("", PromptTone.NONE)


func set_speed_mps(speed_mps: float, forward_speed_mps: float = 0.0) -> void:
	if not is_node_ready():
		return
	var abs_mps := absf(speed_mps)
	var mph := roundi(abs_mps * 2.236936)
	var kmh := roundi(abs_mps * 3.6)
	var gear := ""
	if forward_speed_mps < -0.6:
		gear = "  [REV]"
	elif abs_mps < 0.25:
		gear = "  [PARK]"
	speed_label.text = "%d MPH  ·  %d KM/H%s" % [mph, kmh, gear]


func set_rifle_stance(enabled: bool) -> void:
	if not is_node_ready():
		return
	if enabled:
		stance_label.text = "STANCE: RIFLE"
		stance_label.modulate = Color(0.55, 0.95, 0.68, 1.0)
	else:
		stance_label.text = "STANCE: UNARMED"
		stance_label.modulate = Color(0.84, 0.88, 0.92, 0.9)


func set_prompt(text: String, tone: PromptTone = PromptTone.NORMAL) -> void:
	if not is_node_ready():
		return
	if text.is_empty() or tone == PromptTone.NONE:
		prompt_panel.visible = false
		return
	prompt_panel.visible = true
	prompt_label.text = text
	match tone:
		PromptTone.NORMAL:
			prompt_panel.add_theme_stylebox_override("panel", _normal_prompt_style)
			prompt_label.modulate = Color(0.95, 0.98, 1.0, 1.0)
		PromptTone.WARNING:
			prompt_panel.add_theme_stylebox_override("panel", _warning_prompt_style)
			prompt_label.modulate = Color(1.0, 0.88, 0.56, 1.0)
		PromptTone.BLOCKED:
			prompt_panel.add_theme_stylebox_override("panel", _blocked_prompt_style)
			prompt_label.modulate = Color(1.0, 0.62, 0.60, 1.0)
