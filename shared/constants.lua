VancePay = rawget(_G, 'VancePay') or {}

VancePay.ResourceName = GetCurrentResourceName()

VancePay.IntentStatuses = {
    pending = 'pending',
    awaitingCustomer = 'awaiting_customer',
    awaitingSwipe = 'awaiting_swipe',
    completed = 'completed',
    cancelled = 'cancelled',
    expired = 'expired',
    failed = 'failed',
}

VancePay.TransactionTypes = {
    payment = 'payment',
    refund = 'refund',
}

VancePay.TransactionStatuses = {
    completed = 'completed',
    partiallyRefunded = 'partially_refunded',
    refunded = 'refunded',
}

VancePay.TerminalTypes = {
    fixed = 'fixed',
    portable = 'portable',
    tablet = 'tablet',
}

VancePay.TerminalStatuses = {
    active = 'active',
    disabled = 'disabled',
    archived = 'archived',
}

VancePay.StoreStatuses = {
    active = 'active',
    archived = 'archived',
}

VancePay.StoreSettlementModes = {
    storeBalance = 'store_balance',
    publicAccount = 'public_account',
}

VancePay.EmployeeRoles = {
    owner = 'owner',
    manager = 'manager',
    cashier = 'cashier',
}

VancePay.PaymentMethods = {
    phone = 'phone',
    card = 'card',
}

VancePay.PoliceTicketTypes = {
    notice = 'notice',
    traffic = 'traffic',
}

VancePay.PoliceTicketStyles = {
    aged = 'aged',
    carbon = 'carbon',
}

VancePay.Events = {
    client = {
        openPos = 'vancepay:client:openPos',
        openAdmin = 'vancepay:client:openAdmin',
        openCollections = 'vancepay:client:openCollections',
        openPoliceTicketBook = 'vancepay:client:openPoliceTicketBook',
        openPoliceTicketManager = 'vancepay:client:openPoliceTicketManager',
        openPoliceTicket = 'vancepay:client:openPoliceTicket',
        openCustomerIntent = 'vancepay:client:openCustomerIntent',
        intentUpdated = 'vancepay:client:intentUpdated',
        fixedTerminalsUpdated = 'vancepay:client:fixedTerminalsUpdated',
        refreshLBPhoneState = 'vancepay:client:refreshLbPhoneState',
    },
    server = {
        initPortablePos = 'vancepay:server:initPortablePos',
        initTablet = 'vancepay:server:initTablet',
        initFixedPos = 'vancepay:server:initFixedPos',
        useInventoryItem = 'vancepay:server:useInventoryItem',
        openPoliceTicketManager = 'vancepay:server:openPoliceTicketManager',
        createIntent = 'vancepay:server:createIntent',
        confirmIntent = 'vancepay:server:confirmIntent',
        swipeIntent = 'vancepay:server:swipeIntent',
        cancelIntent = 'vancepay:server:cancelIntent',
        refundTransaction = 'vancepay:server:refundTransaction',
    }
}
