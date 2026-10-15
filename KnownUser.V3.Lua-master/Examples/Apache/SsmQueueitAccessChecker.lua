----------------------------------------------------------------------------------------------------
-- SsmQueueitAccessChecker.lua
----------------------------------------------------------------------------------------------------
-- DESCRIPTION:
--    Queue-it entry point for the SSM MBRS staging web servers (Apache 2.4 on Windows).
--    Runs in the access-checker phase (LuaHookAccessChecker) instead of as a content handler
--    (LuaMapHandler), because the protected paths are served by ProxyPass and mod_proxy would
--    otherwise handle the request before the Lua handler gets a chance to run.
--
--    Settings are kept in this file rather than in SetEnv, because mod_env applies SetEnv in the
--    fixups phase, which runs after the access-checker phase.
--
-- USAGE (httpd.conf):
--    LoadModule lua_module modules/mod_lua.so
--    LuaPackagePath "C:/queueit/SDK/?.lua"
--    LuaPackagePath "C:/queueit/Helpers/?/?.lua"
--    LuaPackagePath "C:/queueit/Handlers/?.lua"
--    <Location "/mbrs">
--        LuaHookAccessChecker "C:/queueit/Examples/Apache/SsmQueueitAccessChecker.lua" queueit_access_check
--    </Location>
----------------------------------------------------------------------------------------------------

-- SETTINGS ----------------------------------------------------------------------------------------
local CUSTOMER_ID = "ssm"
local SECRET_KEY = "544ad03b-1269-4882-93c2-2f20354db8a5a7e8eb9e-92bc-4c1d-8dd0-f59de5aaf26d"
local INT_CONF_FILE = "C:/queueit/qit_integration_configuration.json"
-- Public scheme + host that browsers use. TLS ends at the load balancer, so Apache itself only
-- sees plain http and an internal host; the URL sent to Queue-it must be the public one.
local PUBLIC_BASE_URL = "https://ssmxstaging.ssm.com.my"
-- Paths that must never be queued (static files). Server-to-server callbacks such as the eGHL
-- payment response should also be excluded, either here or as Ignore actions in the GO platform.
local SKIP_EXTENSIONS = { "css", "js", "png", "jpg", "jpeg", "gif", "ico", "svg", "woff", "woff2", "ttf", "map" }
----------------------------------------------------------------------------------------------------

local LOG_TAG = "SsmQueueitAccessChecker.lua"

local function isStaticFile(uri)
    local ext = uri:match("%.([%w]+)$")
    if (ext == nil) then
        return false
    end
    ext = ext:lower()
    for _, skip in ipairs(SKIP_EXTENSIONS) do
        if (ext == skip) then
            return true
        end
    end
    return false
end

function queueit_access_check(r)
    -- r.uri is the path without the query string
    if (r.method == "OPTIONS" or isStaticFile(r.uri)) then
        return apache2.DECLINED
    end

    local success, result = pcall(function()
        local iHelpers = require("KnownUserImplementationHelpers")
        iHelpers.request.getAbsoluteUri = function()
            return PUBLIC_BASE_URL .. r.unparsed_uri
        end

        local file = require("file")
        local intConfJson = file.readAll(INT_CONF_FILE)

        local kuHandler = require("KnownUserApacheHandler")
        return kuHandler.handleByIntegrationConfig(CUSTOMER_ID, SECRET_KEY, intConfJson, r)
    end)

    if (success) then
        return result
    end

    -- Fail open: if the connector breaks, let the visitor through instead of blocking the site.
    r:err(string.format("[%s] Queue-it check failed, request let through: %s", LOG_TAG, tostring(result)))
    return apache2.DECLINED
end
