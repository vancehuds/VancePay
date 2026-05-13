fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vancepay-pos'
author 'Vance'
description 'VancePay payment resource for Qbox/FiveM'
version '1.0.0'
license 'AGPL-3.0-or-later'
provide 'vancepay-pos'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/constants.lua',
    'shared/utils.lua'
}

client_scripts {
    'client/main.lua',
    'client/fixed_terminal_placement.lua',
    'client/pos_interaction.lua',
    'client/payment_flow.lua',
    'client/customer_request.lua',
    'client/lbphone.lua',
    'client/collections.lua',
    'client/police_tickets.lua',
    'client/police_ticket_manager.lua',
    'client/ox_inventory_exports.lua',
    'client/admin.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/kook.lua',
    'server/fivem_log.lua',
    'server/audit.lua',
    'server/permissions.lua',
    'server/stores.lua',
    'server/models.lua',
    'server/terminals.lua',
    'server/banking.lua',
    'server/balance.lua',
    'server/loans.lua',
    'server/police_tickets.lua',
    'server/intents.lua',
    'server/transactions.lua',
    'server/reports.lua'
}

files {
    'html/index.html',
    'html/css/pos.css',
    'html/css/admin.css',
    'html/js/pos.js',
    'html/js/customer.js',
    'html/js/collections.js',
    'html/js/police_ticket.js',
    'html/js/police_ticket_manager.js',
    'html/js/admin.js',
    'html/lbphone/index.html',
    'html/lbphone/app.css',
    'html/lbphone/app.js',
    'html/lbphone/icon.svg'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
    'qbx_core'
}
