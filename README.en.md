# VancePay

Language: [中文](README.md) | [English](README.en.md)

VancePay is a FiveM merchant payment resource for Qbox servers. It includes POS collection, phone/card payments, refunds, store and terminal management, audit logs, and basic reports.

## Current Status

Current features include:

- `payment_intent` driven payment flow
- store, employee, and terminal management data models
- server-side phone/card payment flow with order notes and multi-line item details
- single full refund
- fixed POS, portable POS, and admin tablet client entries
- NUI cashier view, customer confirmation view, admin panel, and `lb-phone` app
- overdue loans, collection tasks, and fuzzy map search areas
- multi-agency paper police tickets, ticket management tablet, and VanceCtifo credit-event sync

## Development Environment

The repository expects these tools for local checks:

- `Lua 5.4`
- `Node.js 18`
- `npm 9`

Run the static check script:

```bash
./scripts/check.sh
```

On Windows PowerShell, you can also run:

```powershell
.\scripts\check.ps1
```

## Dependencies

- `qbx_core`
- `ox_lib`
- `ox_inventory`
- `ox_target`
- `oxmysql`

Optional integrations:

- `lb-phone`, for routing customer-side phone payments into the `VancePay` app
- `vancefivemlog`, for pushing payment, refund, audit, and diagnostic events to an external logging service

## Installation

1. Put this resource under your server `resources` directory.
2. Run [sql/install.sql](sql/install.sql).
3. Make sure dependencies start before this resource in `server.cfg`.
4. Adjust fees, admin groups, and banking adapter settings in [shared/config.lua](shared/config.lua).
5. Create the following items in `ox_inventory`. Use plain item definitions only; do not configure `server.export` or `client.export` on these items to point at `vancepay-pos`.
6. To use the KOOK logging bot, configure `set vancepay_kook_bot_token "Your Bot Token"` and `set vancepay_kook_channel_id "Target Channel ID"` in `server.cfg`, then set `Config.Kook.enabled = true` in [shared/config.lua](shared/config.lua).
7. To use VanceFiveMLog, start `vancefivemlog` before this resource and set `Config.VanceFiveMLog.enabled = true` in [shared/config.lua](shared/config.lua).
8. If customers should confirm or reject payment requests in `lb-phone`, start `lb-phone` before this resource and keep `Config.LBPhone.enabled = true` in [shared/config.lua](shared/config.lua).
9. A fresh install should use [sql/install.sql](sql/install.sql), so `Config.Database.autoMigrate` is disabled by default to avoid repeated startup migrations and `server thread hitch warning`. Only enable migration/backfill options temporarily when upgrading an existing database after taking a backup.

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

Matching item icons are included in [assets/item-icons/README.en.md](assets/item-icons/README.en.md). If you use `ox_inventory`, copy the matching PNG files from `assets/item-icons/png/` into your item image directory and keep the file names unchanged.

If you run `Qbox + ox_inventory` and clicking `vp_tablet`, `portable_pos`, `vp_debt_tablet`, `vp_ticket_book`, `vp_ticket_tablet`, or `vp_police_ticket` does nothing, first confirm that your admin group is included in `Config.AdminGroups` in [shared/config.lua](shared/config.lua). The defaults include `god`, `admin`, and `superadmin`. This resource registers usable item callbacks through `qbx_core:CreateUseableItem` after the server starts.

If startup reports `No such export usePoliceTicketBook` or `No such export usePoliceTicketManager` in resource `vancepay-pos`, your `ox_inventory/data/items.lua` probably still contains fields like:

```lua
server = { export = 'vancepay-pos.usePoliceTicketBook' }
-- or
client = { export = 'vancepay-pos.usePoliceTicketManager' }
```

Remove those `server.export` / `client.export` fields from VancePay items and keep only the plain item definitions above. `ox_inventory` starts before this resource, so referencing `vancepay-pos.xxx` directly in item definitions causes load-order problems.

`fxmanifest.lua` still provides the `vancepay-pos` alias. If your resource directory is not named `vancepay-pos`, old configurations should still remove those `export` fields instead of relying on cross-resource exports.

## Multi-Agency Police Tickets

`Config.PoliceTickets.agencies` in [shared/config.lua](shared/config.lua) can configure ticket headers, watermarks, badges, code prefixes, and ticket colors by job. The defaults include:

- `lspd`: matches `police` / `lspd`, Los Santos Police Department ticket style.
- `lssd`: matches `lssd`, Los Santos Sheriff's Department ticket style.
- `sahp`: matches `sahp`, San Andreas Highway Patrol ticket style.

When an officer creates a ticket, the system writes `ticket_agency` from the officer job. Players reviewing the paper ticket item later will keep the same agency appearance. When adding or renaming enforcement jobs, add the job name to `allowedJobs` and add a matching agency entry or map it in `jobs`. Existing databases need `sql/migrate_to_latest.sql` or temporary auto-migration to add the `ticket_agency` field.

## Ticket Management Tablet

The `vp_ticket_tablet` item manages police tickets:

- regular enforcement members can view and process tickets issued by their own agency
- job bosses can view their agency audit logs
- admins can switch agencies and manage global tickets and audit logs

The tablet supports filtering, searching, detail views, cancelling unpaid tickets, and restoring cancelled tickets to unpaid. Access control still uses `Config.PoliceTickets.allowedJobs`, `Config.PoliceTickets.agencies`, and `Config.AdminGroups`. The `/vpfineadmin` command opens the same management page; its name can be changed through `Config.PoliceTickets.managementCommand.name`.

## Banking Adapter

By default, VancePay uses the `bank` balance from `qbx_core` as the customer account. If your server uses a separate banking resource, adjust [server/banking.lua](server/banking.lua) or the banking config.

To use `p_banking`, set `Config.Banking.adapter` to `p_banking` in [shared/config.lua](shared/config.lua), and confirm that `Config.Banking.pBankingResource` matches your actual resource name.

## Item Details

The cashier supports two layers of item information:

- `Order note`: whole-order note, such as set description, flavor note, table number, etc.
- `Item details`: multiple item lines, each with name, quantity, and unit price; the system sums the order amount automatically.

Limits are configured in [shared/config.lua](shared/config.lua):

- `MaxItemDescriptionLength`
- `MaxItemLines`
- `MaxItemLineNameLength`
- `MaxItemLineQuantity`

## `lb-phone` App Integration

When `lb-phone` is running, the resource registers a preinstalled `VancePay` custom app automatically; customers do not need to download it from an app store. When a customer receives a phone-payment request:

- if `lb-phone` integration is enabled, the request appears in the `VancePay` phone app, where the customer can approve or reject it
- if `lb-phone` is not installed or not started, the original customer confirmation popup remains as fallback

Options are in `Config.LBPhone` in [shared/config.lua](shared/config.lua):

- `enabled`: enable `lb-phone` integration
- `resource`: `lb-phone` resource name
- `appIdentifier` / `appName`: app identifier and display name
- `showPhoneNotification`: whether to send an `lb-phone` notification for new requests
- `openOnNewIntent`: whether to open the app automatically for new requests
- `activityLimit` / `intentLimit`: initial activity and request sync limits

## Overdue Loans and Collections

The overdue-loan sweep writes VanceCtifo credit events for overdue loans and creates public collection tasks. When a loan is fully repaid, VancePay does not delete or resolve the overdue credit event; it updates the same `source_resource + source_ref` idempotency key to a "paid" state and lowers the impact from `Config.Loans.overdueCreditImpact` to `Config.Loans.overduePaidCreditImpact`.

The `vp_debt_tablet` keeps completion state for claimed collection tasks. After the loan is settled, the task is marked completed and clues stop refreshing. VanceCtifo's phone app, regular tablet, admin tablet, and paper profiles can show that credit event and its "paid" state.

Online clues create a configurable fuzzy search circle on the collector's map (`Config.Loans.Collections.mapArea`). The default radius is 350m, with a small center offset. Each clue refresh replaces the old range and does not expose the debtor's exact coordinates.

## Database Migration

`Config.Database` defaults are conservative for production startup performance:

- `autoMigrate = false`: do not run `ALTER TABLE` migrations on every resource start
- `enforceUtf8mb4 = false`: do not scan and convert table collations on startup
- `backfillTransactionRefunds = false`: do not backfill refund summaries on every startup

When upgrading from an older version, back up the database first, temporarily set the required options to `true`, complete one upgrade run, then restore them to `false`.

## KOOK Logging Bot

The resource includes a KOOK channel logger for syncing key business actions to an admin channel:

- audit actions such as stores, employees, terminals, terminal models, and refunds are pushed automatically
- payment intent creation, cancellation, timeout, failure, and successful payment are pushed automatically
- bot token and channel ID are read from `server.cfg` convars first, so secrets do not need to be written into the repository
- disabled by default; set `Config.Kook.enabled = true` explicitly to enable it

Recommended config:

```cfg
set vancepay_kook_bot_token "Your Bot Token"
set vancepay_kook_channel_id "1234567890123456"
```

Options are in `Config.Kook` in [shared/config.lua](shared/config.lua):

- `enabled`: enable KOOK logging
- `rateLimitMs`: queue interval to avoid message bursts
- `mention`: optional KOOK mention syntax
- `categories.audit/intents/transactions/resource`: per-category toggles

If you enable detailed logs, use a dedicated text channel to avoid flooding regular chat.

## VanceFiveMLog Integration

The resource is compatible with the `vancefivemlog` server export. When enabled, it pushes resource start, store/employee/terminal/loan audit actions, payment intent create/cancel/timeout/failure, completed payments, and completed refunds.

Recommended start order:

```cfg
ensure vancefivemlog
ensure vancepay-pos
```

`vancefivemlog` is optional. If it is not installed, VancePay will warn when log pushing is enabled. Options are in `Config.VanceFiveMLog` in [shared/config.lua](shared/config.lua):

- `enabled`: enable VanceFiveMLog pushing
- `resource`: logging resource name, default `vancefivemlog`
- `eventPrefix`: event prefix, generating names such as `vancepay_payment_completed` and `vancepay_audit_refund_transaction`
- `warnIfUnavailable`: warn when the logging resource is not started
- `debug`: print VancePay-side VanceFiveMLog debug output
- `directHttpDiagnostic`: when `/vplogtest` runs, also send a direct backend request; enabled by default
- `endpointConvar` / `apiKeyConvar`: backend endpoint and API key convars for direct diagnostics; defaults reuse `vfl_endpoint` and `vfl_api_key`
- `testCommand`: server diagnostic command, default `/vplogtest`
- `categories.audit/intents/transactions/resource`: per-category toggles

If logs do not appear in the backend, run this in the server console or in game as an admin:

```cfg
vplogtest
```

The command sends `vancepay_diagnostic_test` through the export and calls `Flush()` immediately, then sends `vancepay_diagnostic_http_test` directly to the backend and prints the HTTP status. If the direct request succeeds but the export path fails, check the `vancefivemlog` resource name and state. If the direct request also fails, check `vfl_endpoint`, `vfl_api_key`, firewall rules, and backend logs.

## Resource Structure

Main files:

- [fxmanifest.lua](fxmanifest.lua)
- [shared/config.lua](shared/config.lua)
- [server/main.lua](server/main.lua)
- [client/main.lua](client/main.lua)
- [html/index.html](html/index.html)

## License

This project is released under AGPL-3.0-or-later. See [LICENSE](LICENSE).
