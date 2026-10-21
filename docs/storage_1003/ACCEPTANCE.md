# 1.0.0.3 阶段一验收与复现

最终冻结开发记录：117个Godot脚本通过、零失败，153项Python测试通过且无跳过，包含真实GLPK。Godot全轮期间CAES仅材质补丁落盘，材质相关4脚本7374检查另行通过。这是原开发验收结果，公开整理未重跑测试。

原生复验覆盖Shift范围选择3/5、左拖框选2/5、全选半选状态、Esc取消、实际运行曲线、8种独立储能图标和CAES哑光分色。实际功率/SOC来自模拟，不为截图造数据。此前Shift末项反转已修，并以旧逻辑负对照复现原问题。

未逐台人工遍历全部27类设备详情与所有充放曲线；软件渲染窗口不代表真实GPU性能，不认证长期GUI稳定性或跨平台安装包。进一步气液固氢、醇氨、CO2、变电站和右侧布局改进未包含。阶段二计划不表示已实现。

公开副本不含私人场景、存档槽、设备标识、备份、截图、遥测或运行日志。源码、实际测试与资源保留；文档作隐私/状态整理。历史回归契约与夹具修订的范围见asset_baseline_checks.md。

使用根README的Godot/Python/GLPK依赖。跨语言审计需要先生成确定性合成夹具：

```sh
python3 tests/export_expanded_storage_crosslanguage.py --glpsol /absolute/path/to/glpsol
godot --headless --path . --script res://tests/test_expanded_storage_crosslanguage.gd
```

聚合回归入口为tools/run_storage_1003_regression.py；Python使用unittest discovery。导出脚本须真实求解和独立审计成功才写出夹具。部分历史测试依赖先行生成输出，开发记录不等于干净克隆无前置步骤的保证。
