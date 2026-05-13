Config = Config or {}

Config.Debug = false
Config.Locale = 'zh'
Config.Currency = '$'

Config.BankCardItem = 'bank_card'
Config.PortablePOSItem = 'portable_pos'
Config.TabletItem = 'vp_tablet'

Config.PoliceTickets = {
    enabled = true,
    allowedJobs = { 'police', 'lspd', 'lssd', 'sahp' },
    requireOnDuty = false,
    command = {
        enabled = true,
        name = 'vpfine',
    },
    managementCommand = {
        enabled = true,
        name = 'vpfineadmin',
    },
    ticketBookItem = 'vp_ticket_book',
    managementTabletItem = 'vp_ticket_tablet',
    ticketItem = 'vp_police_ticket',
    paymentAccount = 'police',
    minAmount = 1,
    maxAmount = 50000,
    maxReasonLength = 160,
    targetDistance = 3.0,
    defaultTicketType = 'notice',
    defaultTicketStyle = 'aged',
    defaultAgency = 'lspd',
    agencies = {
        lspd = {
            label = '洛圣都警察局',
            subtitle = 'LOS SANTOS POLICE DEPARTMENT',
            badge = 'LS',
            watermark = 'LSPD',
            codePrefix = 'LS',
            className = 'agency-lspd',
            jobs = { 'police', 'lspd' },
            theme = {
                paper = 'oklch(94% 0.024 84)',
                paperDeep = 'oklch(90% 0.032 82)',
                edge = 'oklch(78% 0.034 78)',
                ink = 'oklch(25% 0.032 72)',
                inkSoft = 'oklch(43% 0.028 72)',
                line = 'oklch(52% 0.035 72 / 0.38)',
                stamp = 'oklch(43% 0.145 28)',
            },
        },
        lssd = {
            label = '洛圣都县警局',
            subtitle = "LOS SANTOS SHERIFF'S DEPARTMENT",
            badge = 'SD',
            watermark = 'LSSD',
            codePrefix = 'SD',
            className = 'agency-lssd',
            jobs = { 'lssd' },
            theme = {
                paper = 'oklch(93% 0.025 96)',
                paperDeep = 'oklch(87% 0.04 98)',
                edge = 'oklch(70% 0.045 105)',
                ink = 'oklch(28% 0.055 118)',
                inkSoft = 'oklch(44% 0.045 112)',
                line = 'oklch(45% 0.055 118 / 0.36)',
                stamp = 'oklch(38% 0.11 125)',
            },
        },
        sahp = {
            label = '圣安地列斯高速巡警',
            subtitle = 'SAN ANDREAS HIGHWAY PATROL',
            badge = 'HP',
            watermark = 'SAHP',
            codePrefix = 'HP',
            className = 'agency-sahp',
            jobs = { 'sahp' },
            theme = {
                paper = 'oklch(94% 0.018 250)',
                paperDeep = 'oklch(88% 0.025 252)',
                edge = 'oklch(72% 0.035 248)',
                ink = 'oklch(26% 0.075 255)',
                inkSoft = 'oklch(43% 0.055 252)',
                line = 'oklch(48% 0.06 252 / 0.34)',
                stamp = 'oklch(41% 0.13 252)',
            },
        },
    },
    ticketTypes = {
        {
            value = 'notice',
            label = '行政处罚告知单',
        },
        {
            value = 'traffic',
            label = '交通违法处罚单',
        },
    },
    ticketStyles = {
        {
            value = 'aged',
            label = '泛黄纸张',
        },
        {
            value = 'carbon',
            label = '碳复写纸',
        },
    },
    ctifoResource = 'VanceCtifo',
    ctifoResourceAliases = { 'vance_ctifo' },
    credit = {
        enabled = true,
        eventType = 'police_ticket',
        paidKeepsImpact = false,
        paidImpact = 0,
        bands = {
            { min = 1, max = 499, impact = -5 },
            { min = 500, max = 1999, impact = -10 },
            { min = 2000, max = 4999, impact = -20 },
            { min = 5000, impact = -35 },
        },
    },
}

Config.MinAmount = 1
Config.MaxAmount = 100000000
Config.MaxDiscount = 50
Config.MaxTip = 10000000
Config.MaxItemDescriptionLength = 120
Config.MaxItemLines = 12
Config.MaxItemLineNameLength = 80
Config.MaxItemLineQuantity = 9999
Config.IntentTimeout = 60
Config.IntentSweepInterval = 10000
Config.TargetingDistance = 3.0
Config.FixedPosInteractDistance = 2.0
Config.FixedPosInteractRadius = 0.35
Config.CardSwipeControl = 38

Config.Animations = {
    portable = {
        scenario = 'WORLD_HUMAN_STAND_MOBILE_UPRIGHT',
        duration = 1500,
    },
    tablet = {
        scenario = 'WORLD_HUMAN_STAND_MOBILE_UPRIGHT',
        duration = 1500,
    },
    swipe = {
        dict = 'anim@mp_player_intmenu@key_fob@',
        clip = 'fob_click',
        duration = 1800,
        flags = 49,
    }
}

Config.EnableFee = true
Config.FeeRate = 0.03
Config.FeePaidBy = 'store'
Config.DefaultTaxRate = 0
Config.CommissionBalanceUnlockSeconds = 24 * 60 * 60

Config.AllowPartialRefund = false
Config.RefundRequireReason = true
Config.RefundTimeLimit = 0
Config.AdminBypassRefundLimit = true
Config.AdminForceRefundAllowsNegativeBalance = true

Config.TransPerPage = 15
Config.DefaultTerminalModelKey = 'standard'
Config.InteractionOnlyTerminalModelKey = 'interaction_only'
Config.InteractionOnlyTerminalModelName = 'interaction_only'

Config.POSModels = {
    standard = {
        model = 'prop_till_01',
        label = '标准 POS 机'
    },
    modern = {
        model = 'prop_till_01_ld',
        label = '现代 POS 机'
    },
    interaction_only = {
        model = Config.InteractionOnlyTerminalModelName,
        label = '无模型交互点',
        interaction_only = true
    }
}

Config.AdminGroups = { 'god', 'admin', 'superadmin' }

Config.Banking = {
    adapter = 'qbx_core',
    moneyType = 'bank',
    qbxResource = 'qbx_core',
    pBankingResource = 'p_banking',
}

Config.Database = {
    autoMigrate = false,
    enforceUtf8mb4 = false,
    backfillTransactionRefunds = false,
}

Config.Kook = {
    enabled = false,
    botToken = '',
    botTokenConvar = 'vancepay_kook_bot_token',
    channelId = '',
    channelIdConvar = 'vancepay_kook_channel_id',
    apiBaseUrl = 'https://www.kookapp.cn/api/v3',
    rateLimitMs = 1000,
    maxMessageLength = 3500,
    maxDetailLength = 1200,
    prefix = '[VancePay]',
    mention = '',
    categories = {
        resource = true,
        audit = true,
        intents = true,
        transactions = true,
    }
}

Config.VanceFiveMLog = {
    enabled = false,
    resource = 'vancefivemlog',
    eventPrefix = 'vancepay',
    warnIfUnavailable = true,
    debug = false,
    directHttpDiagnostic = true,
    endpointConvar = 'vfl_endpoint',
    apiKeyConvar = 'vfl_api_key',
    testCommand = 'vplogtest',
    categories = {
        resource = true,
        audit = true,
        intents = true,
        transactions = true,
    }
}

Config.Notifications = {
    position = 'top',
    duration = 5000,
}

Config.LBPhone = {
    enabled = true,
    resource = 'lb-phone',
    appIdentifier = 'vancepay',
    appName = 'VancePay',
    appDescription = '查看请求、确认付款、管理 VancePay 余额',
    showPhoneNotification = true,
    openOnNewIntent = false,
    activityLimit = 12,
    intentLimit = 20,
    balanceActivityLimit = 20,
}

Config.Loans = {
    enabled = true,
    ctifoResource = 'VanceCtifo',
    ctifoResourceAliases = { 'vance_ctifo' },
    overdueSweepIntervalMs = 5 * 60 * 1000,
    overdueCreditImpact = -60,
    overduePaidCreditImpact = -15,
    minAmount = 500,
    maxAmount = 50000,
    maxActiveLoans = 2,
    historyLimit = 12,
    defaultTermDays = 7,
    products = {
        {
            key = 'excellent',
            label = '卓越授信',
            minScore = 750,
            maxPrincipal = 50000,
            interestRate = 4.0,
            termDays = { 7, 14, 30 },
        },
        {
            key = 'stable',
            label = '稳定授信',
            minScore = 680,
            maxPrincipal = 30000,
            interestRate = 6.5,
            termDays = { 7, 14, 21 },
        },
        {
            key = 'watch',
            label = '观察授信',
            minScore = 600,
            maxPrincipal = 12000,
            interestRate = 10.0,
            termDays = { 7, 14 },
        },
    },
    Collections = {
        enabled = true,
        tabletItem = 'vp_debt_tablet',
        clueMode = 'fuzzy',
        taskLimit = 30,
        claimLimitPerCollector = 1,
        rewardRate = 5,
        mapArea = {
            enabled = true,
            radius = 350.0,
            centerJitter = 120.0,
            color = 5,
            alpha = 90,
            centerSprite = 161,
            centerScale = 0.75,
            showCenterBlip = true,
            route = false,
        },
    },
}

Config.AdminDefaults = {
    storeStatus = 'active',
    terminalStatus = 'active',
    portableRole = 'cashier',
}

Config.BindingCodes = {
    prefix = 'VP',
    length = 6,
    expiryMinutes = 30,
}
