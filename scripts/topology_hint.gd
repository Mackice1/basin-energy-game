extends RefCounted
## Read-only structural facts, never a diagnosis of weather, inventory or dispatch.
const Catalog=preload("res://scripts/device_catalog.gd")
static func for_device(id:int,devices:Array,links:Array)->String:
 var chosen:Dictionary={}
 var kinds:Dictionary={}
 for d in devices:
  kinds[int(d.id)]=str(d.kind)
  if int(d.id)==id:chosen=d
 if chosen.is_empty():return ""
 var kind:String=chosen.kind
 if not (kind in ["wind","pv","load"] or Catalog.is_electric_station(kind) or Catalog.is_electric_storage(kind)):return ""
 var incoming:=false;var outgoing:=false;var station_id:=-2
 for link in links:
  if str(link.get("carrier","electricity_ac"))!="electricity_ac":continue
  var a:=int(link.get("from",-2));var b:=int(link.get("to",-2))
  if b==id:
   incoming=true
   if Catalog.is_electric_station(kind) and Catalog.is_electric_storage(str(kinds.get(a,""))):outgoing=true
  if a==id:outgoing=true
  var peer:int=b if a==id else a if b==id else -2
  if Catalog.is_electric_station(str(kinds.get(peer,""))):station_id=peer
 if Catalog.is_electric_station(kind):
  if not incoming and not outgoing:return "连线提示 · 尚无交流线路；先接电源，再接负荷或外部电网。"
  if not incoming:return "连线提示 · 缺少交流输入线路；请连接电源或电储能。"
  if not outgoing:return "连线提示 · 尚无供电/外送出线；可连接负荷，或点击“连接外部电网”。"
 elif kind=="load":
  if not incoming:return "连线提示 · 负荷尚无交流供电线路；请从汇集站接入。"
  if station_id!=-2:
   var has_source:=false
   for link in links:
    if str(link.get("carrier","electricity_ac"))!="electricity_ac":continue
    var source_id:=int(link.get("from",-2))
    if int(link.get("to",-2))==station_id:
     var source_kind:=str(kinds.get(source_id,""))
     if source_kind in ["wind","pv","steam_turbine","fuel_cell_station"] or Catalog.is_electric_storage(source_kind):has_source=true
   if not has_source:return "连线提示 · 已接汇集站，但上游尚未连接电源或电储能；请补充交流输入线路。"
 else:
  if station_id==-2:return "连线提示 · 尚未接入汇集站；请用“连线”连接交流端口。"
  if kind in ["wind","pv"]:
   var has_sink:=false
   for link in links:
    if str(link.get("carrier","electricity_ac"))!="electricity_ac":continue
    if int(link.get("from",-2))==station_id:has_sink=true
    if int(link.get("to",-2))==station_id and Catalog.is_electric_storage(str(kinds.get(int(link.get("from",-2)),""))):has_sink=true
   if not has_sink:return "连线提示 · 已接汇集站，但该站尚无供电/外送出线；请连接负荷或外部电网。"
 return ""
