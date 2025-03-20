-- Emerald Banking App Server
local DATABASE_FILE = "bank_database"
local LOG_FILE = "server_log"
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

-- Logging function
local function log(message)
    local file = fs.open(LOG_FILE, "a")
    file.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message)
    file.close()
end

-- Session management
local sessions = {}
local function generateToken(username)
    local token = string.format("%x%x", os.time(), math.random(1000, 9999))
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
        log("Account created: " .. data.username)
        return { success = true, message = "Account created successfully" }
    end,

    login = function(data)
        local account = database.accounts[data.username]
        if not account or account.password ~= data.password then
            return { success = false, message = "Invalid username or password" }
        end
        
        local token = generateToken(data.username)
        log("User logged in: " .. data.username)
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
        log("Transfer: " .. username .. " to " .. data.recipient .. " amount: " .. data.amount)
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
        log("Request: " .. username .. " requested " .. data.amount .. " from " .. data.recipient)
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
    end,

    account = function(data, username)
        local account = database.accounts[username]
        if not account then
            return { success = false, message = "Account not found" }
        end
        
        return {
            success = true,
            account = {
                username = username,
                balance = account.balance,
                created_at = account.created_at
            }
        }
    end
}

-- Admin commands
local function listAccounts()
    for username, account in pairs(database.accounts) do
        print("Username: " .. username)
        print("Balance: " .. account.balance)
        print("Created At: " .. account.created_at)
        print("-----------")
    end
end

local function addMoney(username, amount)
    local account = database.accounts[username]
    if not account then
        print("Account not found")
        return
    end
    
    account.balance = account.balance + amount
    saveDatabase()
    log("Added money: " .. amount .. " to " .. username)
    print("Money added successfully")
end

local function viewLog()
    if fs.exists(LOG_FILE) then
        local file = fs.open(LOG_FILE, "r")
        local logData = file.readAll()
        file.close()
        print(logData)
    else
        print("Log file not found")
    end
end

local function shutdown()
    
    saveDatabase()
    rednet.close()
end

-- Main server loop
print("Starting Emerald Banking Server...")
loadDatabase()
rednet.open("back") -- Adjust modem side as needed

-- Parallel execution to handle both rednet and admin commands
parallel.waitForAny(
    function()
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
    end,
    function()
        while true do
            write("> ")
            local input = read()
            local args = {}
            for word in input:gmatch("%S+") do
                table.insert(args, word)
            end
            
            local command = table.remove(args, 1)
            if command == "list_accounts" or command == "list" or command == "la" then
                listAccounts()
            elseif command == "add_money" then
                local username = args[1]
                local amount = tonumber(args[2])
                if username and amount then
                    addMoney(username, amount)
                else
                    print("Usage: add_money <username> <amount>")
                end
            elseif command == "shutdown" or command == "off" or command ==  "stop" then
                print("Shutting down server...")
                saveDatabase()
                shutdown()
                break
            elseif command == "log" then
                viewLog()
            else
                print("Unknown command: " .. command)
            end
        end
    end
)
