local http = require("http")
local https = require("https")
local url = require("url")
local timer = require("timer")
local json = require("json")

local WEBHOOK_URL = "https://discord.com/api/webhooks/1482252401741271080/pVHcdjup7KcdLVdtqzDCMJx_6BLOnk4CwgKN1Bgr3gXRNAtymYe0FdTS8YPnDEVy675L"

---------------------------------------------------------------------
-- Helper: Fetch wiki page HTML via Fandom API
---------------------------------------------------------------------
local function fetchWikiPage(pageName, callback)
    local apiUrl = "https://dandys-world-robloxhorror.fandom.com/api.php" ..
                   "?action=parse&page=" .. pageName ..
                   "&prop=text&format=json&origin=*"

    https.get(apiUrl, function(res)
        local body = ""

        res:on("data", function(chunk)
            body = body .. chunk
        end)

        res:on("end", function()
            local html = body:match([["text"%s*:%s*{%s*"%*"%s*:%s*"(.-)"}]])

            if not html then
                callback(nil)
                return
            end

            html = html
                :gsub("\\n", " ")
                :gsub("\\r", " ")
                :gsub("\\t", " ")
                :gsub('\\"', '"')
                :gsub("\\/", "/")
                :gsub("%s+", " ")

            callback(html)
        end)
    end)
end

---------------------------------------------------------------------
-- Fetch Daily Twisted name
---------------------------------------------------------------------
local function fetchDailyTwisted(callback)
    local apiUrl = "https://dandys-world-robloxhorror.fandom.com/api.php" ..
                   "?action=parse&page=Daily_Twisted_Board&prop=text&format=json&origin=*"

    https.get(apiUrl, function(res)
        local body = ""

        res:on("data", function(chunk)
            body = body .. chunk
        end)

        res:on("end", function()
            local html = body:match([["text"%s*:%s*{%s*"%*"%s*:%s*"(.-)"}]])
            if not html then return callback("Unknown Twisted") end

            html = html
                :gsub("\\n", " ")
                :gsub("\\r", " ")
                :gsub("\\t", " ")
                :gsub('\\"', '"')
                :gsub("\\/", "/")
                :gsub("%s+", " ")

            local section = html:match("occupied by(.-)%.")
            if not section then return callback("Unknown Twisted") end

            section = section:gsub("<.->", ""):gsub("^%s+", ""):gsub("%s+$", "")

            local twisted =
                section:match("(Twisted%s+[%w_]+)") or
                section:match("(Twisted%s+[%w_]+%s+[%w_]+)") or
                "Unknown Twisted"

            callback(twisted)
        end)
    end)
end

---------------------------------------------------------------------
-- Fetch Twisted (image + type + description)
---------------------------------------------------------------------
local function fetchTwistedCard(twisted, callback)
    local twistedPage = twisted:gsub(" ", "_")

    fetchWikiPage(twistedPage, function(html)
        if not html then
            return callback({
                image = nil,
                type = "Unknown",
                description = "No description available.",
                twistedPage = twistedPage
            })
        end

        ----------------------------------------------------
        -- IMAGE: FULL RENDER ONLY (href contains Full_Render.png)
        ----------------------------------------------------
        local realImg =
            html:match('<a[^>]-href="(https://[^"]-Full_Render%.png[^"]-)"') or
            html:match('<a[^>]-href="(https://[^"]-Full%-Render%.png[^"]-)"')

        ----------------------------------------------------
        -- TYPE: match <h3>Type</h3> then <div class="pi-data-value">
        ----------------------------------------------------
        local typeVal =
            html:match('<h3[^>]->%s*Type%s*</h3>%s*<div[^>]-pi%-data%-value[^>]->(.-)</div>')

        if typeVal then
            typeVal = typeVal
                :gsub("<.->", "")   -- remove all HTML tags
                :gsub("^%s+", "")   -- trim left
                :gsub("%s+$", "")   -- trim right
        else
            typeVal = "Unknown"
        end

        ----------------------------------------------------
        -- DESCRIPTION: extract ONLY the Twisted Research quote
        ----------------------------------------------------
        local description = html:match('<td[^>]-font%-style:italic[^>]->(.-)</td>')

        if description then
            description = description
                :gsub("<.->", "")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
        end

        -- fallback if quote table missing
        if not description then
            description = html:match("<p>(.-This Twisted.-)</p>")
            if description then
                description = description:gsub("<.->", ""):gsub("^%s+", ""):gsub("%s+$", "")
            end
        end

        if not description then
            description = "No description available."
        end

        callback({
            image = realImg,
            type = typeVal,
            description = description,
            twistedPage = twistedPage
        })
    end)
end

---------------------------------------------------------------------
-- Send embed (thumbnail layout)
---------------------------------------------------------------------
local function sendWebhookEmbed(twisted, card)
    local parsed = url.parse(WEBHOOK_URL)
    local wikiURL = "https://dandys-world-robloxhorror.fandom.com/wiki/" .. card.twistedPage

    local embed = {
        content = "<@&1483591175234654341> **Daily Twisted!**",
        embeds = {{
            title = twisted,
            url = wikiURL,
            color = 0xE74C3C,

            description = card.description,

            fields = {{
                name = "Type",
                value = card.type,
                inline = false
            }},

            thumbnail = card.image and { url = card.image } or nil,

            footer = { text = "Daily Twisted" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    local payload = json.stringify(embed)

    local options = {
        host = parsed.host,
        path = parsed.path,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #payload
        }
    }

    local req = https.request(options, function() end)
    req:write(payload)
    req:done()
end

---------------------------------------------------------------------
-- Time check (CST/CDT)
---------------------------------------------------------------------
local function isCSTime()
    local t = os.date("*t")
    return t.hour == 19 and t.min == 10
end

---------------------------------------------------------------------
-- Main logic
---------------------------------------------------------------------
local mode = process.argv[2]
local forced = (mode == "send")

local function runBot()
    fetchDailyTwisted(function(twisted)
        fetchTwistedCard(twisted, function(card)
            sendWebhookEmbed(twisted, card)
        end)
    end)
end

if forced then
    runBot()
else
    if isCSTime() then
        runBot()
    end
end
