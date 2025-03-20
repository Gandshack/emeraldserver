-- Emerald Banking App Server
local DATABASE_FILE = "bank_database"
local database = {
    accounts = {},
    transactions = {},
    notifications = {},
    requests = {}
}

-- Database functions
local function saveDatabase()
    local file = fs.open(DATABASE_FILE, "w")
    file.write(textutils.serialize(database))
    file.close()
end

local function loadDatabase()
    if fs.exists(DATABASE_FILE) then
        local file = fs.open(DATABASE_FILE, "r")
        database = textutils.unserialize(file.readAll())
        file.close()
    end
end

-- Session management
local sessions = {}
local function generateToken(username)
    local token = string.format("%x%x", os.epoch("utc"), math.random(1000, 9999))
    sessions[token] = username
    return token
end

local function validateSession(token)
    return sessions[token]
end

-- Request handlers
local handlers = {
    create = function(data)
        if database.accounts[data.username] then
            return { success = false, message = "Username already exists" }
        end
        
        database.accounts[data.username] = {
            password = data.password,
            balance = 0,
            created_at = os.epoch("utc")
        }
        saveDatabase()
        return { success = true, message = "Account created successfully" }
    end,

    login = function(data)
        local account = database.accounts[data.username]
        if not account or account.password ~= data.password then
            return { success = false, message = "Invalid username or password" }
        end
        
        local token = generateToken(data.username)
        return { 
            success = true, 
            message = "Login successful",
            token = token
        }
    end,

    balance = function(data, username)
        local account = database.accounts[username]
        return {
            success = true,
            balance = account.balance
        }
    end,

    transfer = function(data, username)
        local sender = database.accounts[username]
        local recipient = database.accounts[data.recipient]
        
        if not recipient then
            return { success = false, message = "Recipient not found" }
        end
        
        if sender.balance < data.amount then
            return { success = false, message = "Insufficient funds" }
        end
        
        -- Process transfer
        sender.balance = sender.balance - data.amount
        recipient.balance = recipient.balance + data.amount
        
        -- Record transaction
        table.insert(database.transactions, {
            from = username,
            to = data.recipient,
            amount = data.amount,
            timestamp = os.epoch("utc")
        })
        
        saveDatabase()
        return { success = true, message = "Transfer successful" }
    end,

    history = function(data, username)
        local history = {}
        for _, trans in ipairs(database.transactions) do
            if trans.from == username or trans.to == username then
                table.insert(history, trans)
            end
        end
        return { success = true, history = history }
    end,

    request = function(data, username)
        table.insert(database.requests, {
            from = username,
            to = data.recipient,
            amount = data.amount,
            timestamp = os.epoch("utc"),
            status = "pending"
        })
        
        -- Add notification for recipient
        table.insert(database.notifications, {
            user = data.recipient,
            message = username .. " requested " .. data.amount .. " emeralds",
            timestamp = os.epoch("utc"),
            read = false
        })
        
        saveDatabase()
        return { success = true, message = "Request sent" }
    end,

    notifications = function(data, username)
        local notifications = {}
        for _, notif in ipairs(database.notifications) do
            if notif.user == username then
                table.insert(notifications, notif)
            end
        end
        return { success = true, notifications = notifications }
    end
}

-- Main server loop
print("Starting Emerald Banking Server...")
loadDatabase()
rednet.open("right") -- Adjust modem side as needed

while true do
    local sender, message, protocol = rednet.receive("emerald_bank")
    if message and message.action then
        local handler = handlers[message.action]
        local response = { success = false, message = "Invalid request" }
        
        if handler then
            local username = nil
            if message.token then
                username = validateSession(message.token)
            end
            
            if message.action == "create" or message.action == "login" or username then
                response = handler(message.data, username)
            else
                response = { success = false, message = "Authentication required" }
            end
        end
        
        rednet.send(sender, response, "emerald_bank")
    end
end
