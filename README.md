# VancePay
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/License-AGPL--3.0--or--later-blue.svg)](LICENSE)

语言：[中文](README.md) | [English](README.en.md)

VancePay 是一个面向 Qbox 服务器的 FiveM 商户收款资源，包含 POS 收款、手机/刷卡支付、退款、店铺与终端管理、审计日志和基础报表。

## 当前状态

当前功能包括：

- `payment_intent` 驱动的支付流程
- 店铺/员工/终端管理数据模型
- 手机支付与刷卡支付服务端链路，支持收款时填写订单说明与多商品明细
- 单次全额退款
- 固定 POS、便携 POS、管理平板客户端入口
- NUI 收银界面、顾客确认界面、管理面板和 `lb-phone` App
- 贷款逾期、追债任务和地图模糊搜索圈
- 多执法机构纸质罚单、罚单管理平板和 VanceCtifo 信用事件同步

## 开发环境

- `Lua 5.4`
- `Node.js 18`
- `npm 9`

## 依赖

- `qbx_core`
- `ox_lib`
- `ox_inventory`
- `ox_target`
- `oxmysql`

可选集成：

- `lb-phone`，用于把顾客侧“手机支付”接入到手机里的 `VancePay` app
- `vancefivemlog`，用于把支付、退款、审计和资源诊断事件推送到外部日志服务

## 安装

1. 将本资源放入服务器 `resources` 目录。
2. 执行 [sql/install.sql](sql/install.sql)。
3. 在 `server.cfg` 中确保依赖先于本资源启动。
4. 根据服务器经济系统调整 [shared/config.lua](shared/config.lua) 中的手续费、管理员组和银行适配设置。
5. 在 `ox_inventory` 中创建以下物品。只需要基础物品定义，不要在这些物品里配置 `server.export` 或 `client.export` 指向 `vancepay-pos`。
6. 如需 KOOK 日志机器人，在 `server.cfg` 中配置 `set vancepay_kook_bot_token "你的 Bot Token"` 和 `set vancepay_kook_channel_id "目标频道 ID"`，并将 [shared/config.lua](shared/config.lua) 里的 `Config.Kook.enabled` 设为 `true`。
7. 如需接入 VanceFiveMLog，确保 `vancefivemlog` 先于本资源启动，并将 [shared/config.lua](shared/config.lua) 里的 `Config.VanceFiveMLog.enabled` 设为 `true`。
8. 如果你要让顾客在 `lb-phone` 里确认或拒绝付款请求，确保 `lb-phone` 先于本资源启动，并保留 [shared/config.lua](shared/config.lua) 里的 `Config.LBPhone.enabled = true`。
9. 默认依赖 [sql/install.sql](sql/install.sql) 提供完整表结构，因此 `Config.Database.autoMigrate` 默认关闭，避免资源启动时反复执行迁移导致 `server thread hitch warning`。只有在升级旧库且已备份数据库时，才临时开启迁移/补数据开关。

```lua
['bank_card'] = {
    label = '银行卡',
    weight = 10,
    stack = false,
    consume = 0,
    close = true,
},
['portable_pos'] = {
    label = '便携 POS',
    weight = 500,
    stack = false,
    consume = 0,
    close = true,
},
['vp_tablet'] = {
    label = 'VancePay 平板',
    weight = 300,
    stack = false,
    consume = 0,
    close = true,
},
['vp_debt_tablet'] = {
    label = 'VancePay 追债平板',
    weight = 300,
    stack = false,
    consume = 0,
    close = true,
},
['vp_ticket_book'] = {
    label = '警察罚单本',
    weight = 200,
    stack = false,
    consume = 0,
    close = true,
},
['vp_ticket_tablet'] = {
    label = '罚单管理平板',
    weight = 300,
    stack = false,
    consume = 0,
    close = true,
},
['vp_police_ticket'] = {
    label = '警察罚单',
    weight = 10,
    stack = false,
    consume = 0,
    close = true,
}
```

仓库里已附带一套同名物品图标，位于 [assets/item-icons/README.md](assets/item-icons/README.md)。
如果你使用 `ox_inventory`，把 `assets/item-icons/png/` 里的同名 PNG 文件复制到你的物品图片目录并保持同名即可。

如果你的服是 `Qbox + ox_inventory`，但点击 `vp_tablet` / `portable_pos` / `vp_debt_tablet` / `vp_ticket_book` / `vp_ticket_tablet` / `vp_police_ticket` 没反应，先确认你的管理组包含在 [shared/config.lua](shared/config.lua) 的 `Config.AdminGroups`，默认已包含 `god`、`admin`、`superadmin`。本资源会在服务端启动后通过 `qbx_core:CreateUseableItem` 注册这些物品的使用回调。

如果启动时报 `No such export usePoliceTicketBook` / `No such export usePoliceTicketManager` in resource `vancepay-pos`，说明你的 `ox_inventory/data/items.lua` 里还保留了类似下面的字段：

```lua
server = { export = 'vancepay-pos.usePoliceTicketBook' }
-- 或
client = { export = 'vancepay-pos.usePoliceTicketManager' }
```

请把这些 `server.export` / `client.export` 字段从 VancePay 相关物品里删掉，只保留上方的基础物品定义。`ox_inventory` 会早于本资源启动，直接在物品定义里引用 `vancepay-pos.xxx` 会触发启动顺序问题。

本资源的 `fxmanifest.lua` 同时提供了 `vancepay-pos` 别名；如果你的资源目录名不是 `vancepay-pos`，旧配置仍建议按上面删掉 `export` 字段，而不是继续依赖跨资源 export。

## 多执法机构罚单

`shared/config.lua` 的 `Config.PoliceTickets.agencies` 可按岗位配置罚单抬头、水印、徽章、票据编号前缀和票面配色。默认已配置：

- `lspd`：匹配 `police` / `lspd`，洛圣都警察局票面。
- `lssd`：匹配 `lssd`，洛圣都县警局票面。
- `sahp`：匹配 `sahp`，圣安地列斯高速巡警票面。

开单时系统会按开单人的 job 自动写入 `ticket_agency`，玩家之后通过纸质罚单物品复查时也会保持同一机构外观。新增或改名执法机构时，把 job 名加入 `allowedJobs`，并在 `agencies` 中添加同名机构或在 `jobs` 里映射即可。老数据库需要执行 `sql/migrate_to_latest.sql` 或开启自动迁移来补充 `ticket_agency` 字段。

## 罚单管理平板

新增物品 `vp_ticket_tablet`（显示名：罚单管理平板）用于管理罚单：

- 普通执法职业成员只能查看和处理自己职业对应机构开具的罚单。
- 职业 Boss 可查看本机构罚单审计日志。
- 管理员可切换机构并管理全局罚单及审计日志。

当前平板支持筛选、搜索、查看详情、取消未缴罚单，以及将已取消罚单恢复为未缴。使用权限仍沿用 `Config.PoliceTickets.allowedJobs`、`Config.PoliceTickets.agencies` 和 `Config.AdminGroups`。也可以使用命令 `/vpfineadmin` 直接打开同一个管理页面，命令名可通过 `Config.PoliceTickets.managementCommand.name` 调整。

## 银行适配

默认实现使用 `qbx_core` 的 `bank` 余额作为顾客账户。若服务器已有独立银行资源，可在 [server/banking.lua](server/banking.lua) 替换适配层实现。

如果使用 `p_banking`，可将 [shared/config.lua](shared/config.lua) 中的 `Config.Banking.adapter` 改为 `p_banking`，并确认 `Config.Banking.pBankingResource` 与实际资源名一致。

## 商品明细

收银端现在支持两层商品信息：

- `订单说明`：整单备注，例如套餐说明、口味备注、桌号等
- `商品明细`：多条商品项，每条包含名称、数量、单价，系统会自动汇总为订单金额

相关限制位于 [shared/config.lua](shared/config.lua)：

- `MaxItemDescriptionLength`
- `MaxItemLines`
- `MaxItemLineNameLength`
- `MaxItemLineQuantity`

## `lb-phone` App 集成

资源现在会在检测到 `lb-phone` 已启动后，自动注册一个预装的 `VancePay` 自定义 app，不需要顾客再去应用商店下载。顾客收到“手机支付”请求时：

- 如果启用了 `lb-phone` 集成，请求会进入手机里的 `VancePay` app，顾客可在 app 中确认或拒绝
- 如果没有安装或没有启动 `lb-phone`，仍然使用本资源原本的顾客确认弹窗作为兜底

可调项位于 [shared/config.lua](shared/config.lua) 的 `Config.LBPhone`：

- `enabled`: 是否启用 `lb-phone` 集成
- `resource`: `lb-phone` 资源名
- `appIdentifier` / `appName`: app 标识与显示名
- `showPhoneNotification`: 收到请求时是否发送 `lb-phone` 通知
- `openOnNewIntent`: 收到请求时是否自动打开 app
- `activityLimit` / `intentLimit`: app 初始同步的请求与活动数量

## 贷款逾期与追债

贷款逾期扫描会为逾期贷款写入 VanceCtifo 信用事件，并生成公开追债任务。贷款还清后，VancePay 不会删除或解除这条逾期信用事件，而是用同一个 `source_resource + source_ref` 幂等更新为“已还清”，并把影响从 `Config.Loans.overdueCreditImpact` 降到 `Config.Loans.overduePaidCreditImpact`。

追债平板 `vp_debt_tablet` 会保留已领取任务的完成状态；贷款结清后任务标记为已完成，线索停止刷新。VanceCtifo 的手机 App、普通平板、管理员平板和纸质档案会显示该信用事件及“已还清”状态。

在线线索会在收债人的地图上生成一个可配置的模糊搜索圈（`Config.Loans.Collections.mapArea`）；默认半径 350m，并对圆心做轻微偏移。每次刷新线索会替换旧范围，不直接暴露债务人的精确坐标。

## 数据库迁移

`Config.Database` 默认值偏向生产启动性能：

- `autoMigrate = false`: 不在资源启动时自动跑 `ALTER TABLE` 迁移
- `enforceUtf8mb4 = false`: 不在启动时扫描并转换表排序规则
- `backfillTransactionRefunds = false`: 不在每次启动时全表回填退款汇总

如果你是从旧版本升级，先备份数据库，再临时把相应开关设为 `true`，完成一次升级后再恢复为 `false`。

## KOOK 日志机器人

资源内置了一个 KOOK 频道日志推送器，适合把关键经营行为同步到管理频道：

- 店铺、员工、终端、终端模型、退款等审计动作会自动推送。
- 支付订单的创建、取消、超时、失败，以及支付成功也会自动推送。
- 机器人密钥和频道 ID 优先从 `server.cfg` 的 convar 读取，避免把敏感信息写进仓库。
- 默认关闭，需要在 `Config.Kook.enabled` 中显式开启。

建议配置：

```cfg
set vancepay_kook_bot_token "你的 Bot Token"
set vancepay_kook_channel_id "1234567890123456"
```

可选项位于 [shared/config.lua](shared/config.lua) 的 `Config.Kook`：

- `enabled`: 是否启用 KOOK 日志
- `rateLimitMs`: 发送队列间隔，避免短时间内连续刷屏
- `mention`: 需要时可填写 KOOK 的提醒语法
- `categories.audit/intents/transactions/resource`: 分类别开关

如果你准备开启详细日志，建议单独建一个文字频道，避免把日常聊天频道刷满。

## VanceFiveMLog 接入

资源已兼容 `vancefivemlog` 的服务端 export。启用后会推送资源启动、店铺/员工/终端/贷款等审计动作、支付订单创建/取消/超时/失败、支付完成和退款完成事件。

推荐启动顺序：

```cfg
ensure vancefivemlog
ensure vancepay-pos
```

`vancefivemlog` 是可选资源；如果未安装，VancePay 会在启用日志推送时提示资源不可用。可选项位于 [shared/config.lua](shared/config.lua) 的 `Config.VanceFiveMLog`：

- `enabled`: 是否启用 VanceFiveMLog 推送
- `resource`: 日志资源名，默认 `vancefivemlog`
- `eventPrefix`: 事件名前缀，默认生成 `vancepay_payment_completed`、`vancepay_audit_refund_transaction` 等事件
- `warnIfUnavailable`: 日志资源未启动时是否在控制台提示
- `debug`: 是否输出 VancePay 侧的 VanceFiveMLog 发送调试信息
- `directHttpDiagnostic`: 执行 `/vplogtest` 时是否额外直接请求 VanceFiveMLog 后端，默认开启
- `endpointConvar` / `apiKeyConvar`: 直接诊断使用的后端地址与 API Key convar，默认复用 `vfl_endpoint` 和 `vfl_api_key`
- `testCommand`: 服务端诊断命令，默认 `/vplogtest`
- `categories.audit/intents/transactions/resource`: 分类别开关

如果后台没有出现 VancePay 日志，先在服务器控制台或管理员游戏内执行：

```cfg
vplogtest
```

该命令会通过 export 发送 `vancepay_diagnostic_test` 并立即调用 `Flush()`，同时直接请求后端发送 `vancepay_diagnostic_http_test` 并打印 HTTP 状态码。如果直接请求成功但 export 路径失败，检查 `vancefivemlog` 资源名和启动状态；如果直接请求也失败，检查 `vfl_endpoint`、`vfl_api_key`、防火墙和后端日志。

## 资源结构

资源结构遵循设计文档，主要文件如下：

- [fxmanifest.lua](fxmanifest.lua)
- [shared/config.lua](shared/config.lua)
- [server/main.lua](server/main.lua)
- [client/main.lua](client/main.lua)
- [html/index.html](html/index.html)

## 许可证

本项目以 AGPL-3.0-or-later 发布，详见 [LICENSE](LICENSE)。
