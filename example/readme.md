# GoFire 示例插件

本目录包含 4 个 SourceMod 示例插件，用于演示 GoFire 自定义玩法、模式参数修改、钩子和基础能力扩展的写法。

## dm_random.sp

`dm_random` 实现了“终结者大战人类英雄”的个人竞技玩法。

插件在玩家死亡后随机切换阵营，并在玩家复活后随机选择角色：

- T 阵营随机变为大终结者相关角色。
- CT 阵营随机变为猎手/人类英雄相关角色。
- 每次复活都会重新随机一次，使整局保持高强度乱斗节奏。

该示例加载了 `game.fire` 中的签名和偏移，通过 SDKCall 调用 GoFire 内部函数：

- `CCSPlayer::ConvertTeam`
- `CCSGameRules::OnPlayerSelect`
- `CCSPlayer::iFireMenu` 偏移

它不仅是普通 SourceMod 插件例子，也展示了如何通过 gamedata 来桥接 GoFire 游戏逻辑。

适合参考的方向：

- 通过事件 `player_death`、`player_spawn` 驱动模式逻辑。
- 使用 SDKCall 调用游戏内部函数。
- 使用 gamedata 读取签名和玩家对象偏移。
- 通过插件快速定制小型娱乐玩法。

## nano_buffmodify.sp

`nano_buffmodify` 是使用 SourceMod 修改生化模式乱斗 BUFF 的示例。

插件在每回合开始后延迟 1 秒修改 GameRules 属性：

- `m_iAttribute1 = 1`：设置为“致命一击”。
- `m_iAttribute2 = 8`：设置为“额外提供红色补给箱”。

这个示例展示了如何在不修改 C++ 代码的情况下，通过 SourceMod 对 GoFire 生化模式的回合参数进行快速调整。

适合参考的内容：

- 在 `round_start` 后延迟修改模式数据。
- 使用 `GameRules_SetProp` 写入 GameRules 属性。
- 快速测试不同乱斗 BUFF 组合。

## damage_multiplier.sp

`damage_multiplier` 是一个使用 SDKHooks 修改玩家对玩家伤害倍率的示例。

插件会为进入服务器的玩家挂接 `SDKHook_OnTakeDamage`，在伤害发生时按配置倍率修改伤害值。默认倍率为 `2.0`，也就是玩家之间的伤害翻倍。

可用 ConVar：

- `sm_damage_multiplier`：伤害倍率，默认 `2.0`，范围 `0.1` 到 `100.0`。
- `sm_damage_enabled`：是否启用插件，`1=启用`，`0=禁用`。
- `sm_damage_log`：是否在 SourceMod 日志中记录每次伤害修改，`1=启用`，`0=禁用`。

插件会自动生成并读取配置文件：

```text
cfg/sourcemod/damage_multiplier.cfg
```

适合参考的内容：

- 使用 `SDKHook_OnTakeDamage` 修改玩家伤害。
- 过滤世界伤害、无效实体和非玩家攻击者。
- 使用 ConVar 控制插件开关、倍率和日志输出。
- 使用 `AutoExecConfig` 生成插件配置文件。

## doublejump.sp

`doublejump` AI 生成的二段跳插件示例。

插件允许玩家在空中再次按跳跃键触发额外跳跃，并提供多个 ConVar 用于调整行为：

- `sm_doublejump_enable`：是否启用插件。
- `sm_doublejump_team`：限制可使用二段跳的阵营，`0=全部`，`2=T`，`3=CT`。
- `sm_doublejump_extra`：每次滞空允许的额外跳跃次数。
- `sm_doublejump_velocity`：空中跳跃时的向上速度。
- `sm_doublejump_cooldown`：两次空中跳跃之间的最短间隔。
- `sm_doublejump_nofalldamage`：是否阻止摔落伤害。
- `sm_doublejump_announce`：是否在出生后提示玩家。

示例通过 `OnPlayerRunCmd` 检测玩家刚按下跳跃键的瞬间，保留水平速度并替换 Z 轴速度，从而实现比较自然的二段跳手感。

适合参考的内容：

- 使用 `OnPlayerRunCmd` 编写移动能力插件。
- 处理按键边沿触发，避免长按跳跃连续触发。
- 使用 ConVar 控制插件行为。
- 使用 SDKHooks 拦截摔落伤害。
- 处理梯子、水中、noclip 等不适合触发二段跳的状态。

## 编译说明

使用 GoFire 游戏目录下的 SourceMod 编译器 spcomp 编译。

编译后将生成的 `.smx` 放入服务器的 `addons/sourcemod/plugins` 目录即可加载。

## 注意事项

- 示例插件都包含了地图结束自卸载逻辑，如需常驻运行，可以移除对应的 `OnMapEnd` 卸载代码。
- `damage_multiplier.sp` 默认只修改玩家攻击玩家造成的伤害，没有处理世界伤害或地图实体伤害。
