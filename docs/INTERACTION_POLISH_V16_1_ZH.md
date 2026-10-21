# V16.1 操作与画面打磨验收

2026-10-16；仍为 schema 7 / model 16。基于已核对全部 769 文件的 V16 冻结工程，未新增设备类别；尺寸、库存、能量积分与联合电热调度模型保持原有边界。

## 操作

- 单击设备或厂站统一选中，显示名称、详情及金色高亮；厂站选中后用“进入厂站”或双击进入。返回保留基地镜头和厂站选中。
- 左键拖动选中对象显示米制安装区与预览。按住位置与设备的偏移保持不变；松开合法位置才提交一次撤销记录。重叠、越界、UI 上松开、失焦及取消不修改原位置。非法原因显示在提示区。
- Esc 逐层取消当前拖动/建设/连线、清除选择，再返回基地。站内“撤销”按钮与 Ctrl-Z / Cmd-Z 使用同一撤销栈；撤销站内移动后仍留在站内。
- 连线突出起点和兼容终点，悬停显示载体、方向、温区及容量；不合法连接显示原因，取消清理临时线路。端口标记与实际米制位置一致。
- 聚焦选中与全景分开，F 聚焦；镜头限距、地面净空及异常值恢复防止过近穿地。UI 上开始的镜头拖动不会传到场景，编辑文本时不会误触 WASD。
- 只显示选中、悬停或连线必要标注，标签按屏幕像素限制，避免远处巨大文字；选中高亮优先于悬停。右侧单位列对齐，技术尺寸与详细状态折叠。

## 实际验收

- 最终完整回归：46 套 Godot、330,488 项检查，另 45 项 Python / 真实 GLPK 测试，全部通过。运行前后源码哈希一致。详见 `evidence/polish/VALIDATION.md` 与 `regression_summary.json`。
- 新增交互检查 105 项、站内 80 项、标注与镜头 318 项，覆盖有效/无效/取消拖动、一次撤销、UI 隔离、兼容连线、镜头与非零库存保持。
- 原生 X11 鼠标键盘实测：建造、选中、拖动提交/取消、UI 松开、UI 镜头阻断、连线、单击进入、站内重叠拒绝、移动撤销、逐层返回、键盘存档。14 项权威状态对照全通过，见 `native_mouse_checks.json`。这组操作暂停仿真以分辨 UI 引发的意外变化；运行态时钟/库存保持另由回归覆盖。
- 实际保存的 9 设备 / 9 连线场景由新进程读回，再执行真实联合电热 GLPK：22 项通过，optimal，原始决策独立守恒审计通过，世界和输入存档不变。记录见 `native_restart_solver_record.json`。
- 完整图形场景另有 22 项检查、独立重启 7 项检查，保存的非零热库存与 600 秒时钟保持。此组使用场景事件注入，与上述原生鼠标实测分开记录。

## 最终图像和操作录像

以下路径均相对 `evidence/polish/`：

- `final_native_connected.png`：原生点击新增变电站 #8 至电网连接。
- `final_native_station_undo.png`：站内真实拖动后 Ctrl-Z 恢复，选择和站内视图保留。
- `final_enter_button.png`：原生单击进入按钮成功。
- `polish_base_overview.png`、`polish_facility_selected.png`、`polish_interior_selected.png`：干净场景展示图。
- `polish_interior_invalid_move.png`：非法预览与原设备并存。
- `polish_restarted_interior.png`：独立进程读档后的站内。
- `native_operation_clip.mp4`：20.6 秒真实 X11 录屏，包含站内移动、撤销与镜头旋转。10 fps 为录像采样率，不代表游戏渲染性能。

早期 `08_link_created.json`、`14_inside_undo.json` 等文件保留了修复前问题，不能作为最终成功证据；最终原生检查使用 `final_*.json` 与 `native_mouse_checks.json`。

## 性能与边界

同场景、同相机、同视口串行配对的 146 项一致性核验全通过。云 llvmpipe 平均 FPS：基地暂停 4.30、运行 4.51；站内暂停 7.19、运行 6.58。对应 V16 平均帧时变化为 +0.1%、−3.2%、−16.5%、+1.9%。单轮宿主波动明显，不能称流畅或稳定提速。完整原始样本、物理采样审核与方法见 `evidence/polish/performance/COMPARISON_POLISH.md`。物理仍按原有逐帧时间推进，未降低物理采样；交互标注刷新节流不影响能量积分。真实米制设备没有缩小来腾地。真实 GPU、所有平台导出和设备数据校准不在本轮已验证范围。

## 复现入口

完整回归使用 `BASIN_TEST_HOME=/tmp/basin-polish-full bash tests/run_v13.sh`；需 Godot 4.6.3、Python 与 glpsol 可用。图形验收见 `evidence/polish/run_capture_validation.sh`。原生交互启动器为 `bash tests/run_native_polish.sh`，向其标准输入发送 `tests/native_x11_driver.py` 所示 JSON 命令；运行中 F10 将权威快照写入 `evidence/polish/native_mouse_state.json`。原生启动器仅做 shell 语法核验，实际已完成的操作采用同一 Xorg/Godot/驱动组合手工启动。
