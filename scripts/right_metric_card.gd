extends PanelContainer
## Presentation-only card. Readout columns align inside a group, never an entire
## spreadsheet. Units are non-wrapping; the raw value remains in the tooltip.
const ThemeStyle=preload("res://scripts/ui_theme.gd")
var body:VBoxContainer
var heading:Label
func _init():
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel",ThemeStyle.panel(Color("202e3b"),12,10))
	body=VBoxContainer.new();body.add_theme_constant_override("separation",8);add_child(body)
	heading_placeholder()
func heading_placeholder():
	heading=Label.new();heading.add_theme_font_size_override("font_size",16);heading.add_theme_color_override("font_color",Color("edf3f7"));heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(heading)
func setup(title:String)->VBoxContainer:
	heading.text=title;heading.visible=title!="";return body
static func readout(parent:Node,title:String,unit:String,big:bool=false)->Dictionary:
	var container:Container=VBoxContainer.new() if big else HBoxContainer.new();parent.add_child(container)
	container.add_theme_constant_override("separation",8)
	var caption:=Label.new();caption.text=title;caption.add_theme_font_size_override("font_size",14);caption.add_theme_color_override("font_color",Color("b3c1cd"));caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;container.add_child(caption)
	var row:Container=container
	if big:row=HBoxContainer.new();row.add_theme_constant_override("separation",8);container.add_child(row)
	var value:=Label.new();value.text="0.000";value.add_theme_font_size_override("font_size",30 if big else 17);value.add_theme_color_override("font_color",Color("edf3f7"));value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.custom_minimum_size.x=92;value.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if big:value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(value)
	var units:=Label.new();units.text=unit;units.add_theme_font_size_override("font_size",11);units.add_theme_color_override("font_color",Color("b3c1cd"));units.custom_minimum_size.x=66;units.autowrap_mode=TextServer.AUTOWRAP_OFF;units.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;row.add_child(units)
	value.set_meta("unit",unit)
	return {"caption":caption,"value":value,"unit":units,"row":container}
static func number(value:float,decimals:int=3)->String:
	if not is_finite(value):return "—"
	# Preserve tiny nonzero readings instead of silently presenting them as zero.
	if (absf(value)>0.0 and absf(value)<pow(10.0,-decimals)) or absf(value)>=9999.9995:
		var exponent:=int(floor(log(absf(value))/log(10.0)))
		var mantissa:=value/pow(10.0,exponent)
		if absf(snappedf(mantissa,0.01))>=10.0:mantissa/=10.0;exponent+=1
		return "%.2fe%s%02d"%[mantissa,"+" if exponent>=0 else "-",absi(exponent)]
	return ("%."+str(decimals)+"f")%(0.0 if value==0.0 else value)
static func set_number(target:Label,value:float,decimals:int=3):
	target.text=number(value,decimals)
	target.tooltip_text=str(value)+" "+str(target.get_meta("unit",""))
