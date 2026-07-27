# 突围模式拆分说明

`escape_mod.sp` 是通用突围规则插件，负责上下半场计时、突围次数、持续复活、攻守交换、胜负判定、HUD、突围奖励、BOT 突围目标以及 CT BOT 驻点防守。
通用反馈层还提供突围点冷却倒计时、全服及个人成功提示、出口附近防守聊天提示、可选的击杀栏突围事件和枪械弹药补给。

只在对应的地图配置文件开启时，插件才会在该地图上启用。

## CARGOSHIP 远洋货轮

`#bottle_CARGOSHIP.bsp` 是一张 GoldSrc BSP 30版本 的地图，共有 46 个实体，作者是 瓶子丶bottle  。
其中包含 8 个 `info_player_deathmatch` 出生点、8 个 `info_player_start`出生点和 1 个 `func_bomb_target`，但没有触发器、可破坏障碍或脚本实体。

因此，这张地图通过配置中的坐标判定玩家是否进入可见的蓝色突围圆台，并由通用插件移除爆破目标和 C4，避免原生爆破规则提前结束回合。

BOT 导航目标与突围区域中心为 `-822 -8 -795`，对应地图中的蓝色圆台。
突围区域使用球形判定，初始半径为 `80`；Z 坐标与同层玩家出生高度一致。
如果实测发现判定范围与圆台边缘不够贴合，只需在地图配置中调整半径，无需修改 SourcePawn 代码。

### CT BOT 驻点防守

GoFire 的 `MOD_ESCAPE` 在 BOT 场景选择上属于死亡竞赛，因此仅保留或创建 `func_bomb_target` 并不会触发经典爆破模式的 CT 防守行为。
GoFire 的 `cs_bot` 实体现在提供 `SetGuardGoal` / `ClearGuardGoal` Input，复用原生 bombsite 的 `GUARD_BOMB_ZONE`、`Hide` 和 `OPPORTUNITY_FIRE` 行为。
插件通过 `AcceptEntityInput` 传入目标坐标和搜索范围，不需要 hook，也不依赖 `game.fire` 中的函数签名。
通用插件只负责从CT阵营中选择一部分bot，并把突围区域中心交给原生看守逻辑：

- `defender_guard_enabled`：是否启用 CT BOT 驻点防守。
- `defender_guard_ratio`：参与驻守的 CT BOT 比例，CARGOSHIP 默认为 `0.45`。
- `defender_guard_min` / `defender_guard_max`：驻守 BOT 数量的下限和上限。
- `defender_guard_range`：围绕突围区域搜索看守掩体的最大范围，CARGOSHIP 默认为 `350`。
- `defender_guard_anchor`：是否从守卫组中指定一名贴点 BOT；CARGOSHIP 开启后，该 BOT 会直接站到突围点上。

除贴点 BOT 外，被选中的守卫会在范围内随机选择未被占用的 `IN_COVER` 导航掩体。
原生 Hide 状态会正常观察、交战，并在 30–60 秒后重新选择掩体；插件不冻结移动，也不强制所有守卫蹲下。
未被选中的 CT BOT 继续使用原生 AI 自由行动。CARGOSHIP 最多只选 3 个驻守 BOT，避免主要防守力量全部集中在出口。

以下功能可分别通过地图配置开关：

- `success_killfeed`：是否在击杀栏显示突围事件。
- `refill_ammo`：突围成功后是否补充主、副武器备弹。

出口附近阵亡的聊天提示有效距离由 `defense_distance` 控制，突围点冷却倒计时使用 `escape_cooldown` 设置的时长。

## Temple 隐匿之地
《隐匿之地》地图作者是：风流倜傥你杰森，于2019年发布于CSGO创意工坊。
https://steamcommunity.com/sharedfiles/filedetails/?id=1646684979
`cf_tem.sp` 和 `cf_tem_spr.sp` 是 隐匿之地 地图专用的 突围模式插件 
也是从该地图内置的vscript脚本移植而来，脚本作者：DazaiNerau 

地图包含大量与地图绑定的 VScript/Hammer 行为，
包括 3 个具名可破坏障碍、2 个突围触发器、材质代理、粒子效果、武器房按钮、传送、文字实体以及硬编码的Hammer ID。
大部分功能都交给了插件去辅助管理。

### BOT 破门辅助

`cf_escape_botai.sp` 是突围模式的 BOT 破门辅助插件，用于弥补原生 BOT 不会主动攻击地图目标障碍的问题。插件只处理alive、且 `targetname` 为 `rusher` 的BOT；
当其视野内存在名为 `door1`、`door2` 或 `door3` 的有效 `func_breakable` 时，会选择距离最近且可见的目标，持续朝门瞄准，距离较远时向前移动，并使用枪械开火。面
对障碍时还可强制切回主武器，避免 BOT 持雷发呆；目标短时锁定用于减少原生 AI 抢夺视角造成的瞄准抖动。
该插件不负责创建、重命名或控制障碍流程，这些地图逻辑仍由 `cf_tem.sp` / `cf_tem_spr.sp` 管理。

相关参数均可通过 ConVar 调整：`sm_cf_escape_botai_enable` 控制总开关，`sm_cf_escape_botai_distance` 和 `sm_cf_escape_botai_fov` 控制搜索距离与视野范围，`sm_cf_escape_botai_forward_distance` 和 `sm_cf_escape_botai_forward_speed` 控制靠近障碍的行为，`sm_cf_escape_botai_attack_cooldown` 控制开火间隔，`sm_cf_escape_botai_block_grenades` 控制是否切回主武器，`sm_cf_escape_botai_lock_time` 控制目标锁定时间。

