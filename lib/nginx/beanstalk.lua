-- Copyleft (C) 2013 Live Long and Prosper

local tcp

if _G.standalone then
    local socket = require("socket.core")
    tcp = socket.tcp 
else
    tcp = ngx.socket.tcp
end

local sub = string.sub
local gsub = string.gsub
local format = string.format
local match = string.match
local strlen = string.len
local insert = table.insert
local concat = table.concat
local remove = table.remove
local setmetatable = setmetatable
local type = type
local error = error
local pairs = pairs
local print = print
local tonumber = tonumber


module(...)

_VERSION = "0.01"

local DEFAULT_HOST = "localhost"
local DEFAULT_PORT = 11300

local DEFAULT_PRIORITY = 2 ^ 32 - 1
local DEFAULT_DELAY = 0
local DEFAULT_TTR = 120



local function _split(line, sep)
    local sep, fields = sep or ":", {}
    local pat = format("([^%s]+)", sep)

    gsub(line, pat, function(c) 
        fields[#fields+1] = c 
    end)

    return fields
end


local function _readable_error(indicator)
    local errors = {
        ["OUT_OF_MEMORY"]= "out of memory",
        ["INTERNAL_ERROR"]= "internel error",
        ["BAD_FORMAT"]= "bad format",
        ["UNKNOWN_COMMAND"]= "unknown command",
        ["EXPECTED_CRLF"]= "expect CRLF",
        ["JOB_TOO_BIT"]= "job too big",
        ["DRAINING"]= "server in drain mode",
        ["DEADLINE_SOON"]= "deadline soon",
        ["TIMED_OUT"]= "timedout",
        ["NOT_FOUND"]= "job not found",
    }

    for key, msg in pairs(errors) do
        if key == indicator then return msg end
    end

    return indicator
end


local function _interact(sock, request, expected)
    local bytes, err = sock:send(request)
    if not bytes then
        return nil, "send failed " .. err
    end

    local line, err, partial = sock:receive("*l")
    if not line then
        return nil, "read reply failed " .. err
    end

    local parts = _split(line, " ")

    for _, indicator in pairs(expected) do
        if parts[1] == indicator then
            remove(parts, 1)
            return parts
        end
    end

    return nil, _readable_error(parts[1])
end


--
-- public methods
--
function new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    return setmetatable({sock = sock}, {__index = _M})
end


function set_timeout(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(...)
end


function set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function connect(self, host, port) 
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    host = host or DEFAULT_HOST
    port = port or DEFAULT_PORT

    return sock:connect(host, port)
end


function put(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if type(args.data) ~= "string" then
        return nil, "not valid payload"
    end

    args.priority = args.priority or DEFAULT_PRIORITY
    args.ttr = args.ttr or DEFAULT_TTR
    args.delay = args.delay or DEFAULT_DELAY

    local reply, err = _interact(sock, concat{
            "put ", args.priority, " ", args.delay, " ", 
                args.ttr, " ", #args.data, "\r\n",
                args.data, "\r\n"
        }, {"INSERTED", "BURIED"})

    if not reply then
        return nil, err
    end

    return reply[1]
end


function use(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    tube = args.tube or "default"

    local retval, err = _interact(sock, concat{
            "use ", tube, "\r\n"
        }, {"USING"})

    if not retval then
        return nil, err
    end

    return retval[1]
end


function reserve(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local result, request = {}

    if args.timeout then
        request = concat{"reserve-with-timeout ", args.timeout, "\r\n"}
    else
        request = "reserve\r\n"
    end

    local retval, err = _interact(sock, request, {"RESERVED"})
    if not retval then
        return nil, err
    end

    result.id = tonumber(retval[1])

    local line, err = sock:receive(retval[2])
    if not line then
        return nil, "failed to receive job body: " .. (err or "")
    end

    result.data = line

    line, err = sock:receive(2) -- discard the trailing CRLF
    if not line then
        return nil, "failed to receive CRLF: " .. (err or "")
    end

    return result
end


function delete(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if type(args.id) ~= "number" then
        return nil, "job id should be a number"
    end

    local retval, err = _interact(sock, concat{
            "delete ", args.id, "\r\n"
        }, {"DELETED"})
    if not retval then
        return nil, err
    end

    return 1
end


function release(self, args)
end
function bury(self, args)
end
function touch(self, args)
end


function watch(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    tube = args.tube or "default"

    local reply, err = _interact(sock, concat{
            "watch ", tube, "\r\n"
        }, {"WATCHING"})
    
    if not reply then
        return nil, err
    end

    return reply[1]
end

function ignore(self, args)
end
function peek(self, args)
end
function kick(self, args)
end
function stats(self, args)
end


function quit(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    sock:send("quit\r\n")

    sock:close() 
end


local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        error('attempt to write to undeclared variable "' .. key .. '"')
    end
}

setmetatable(_M, class_mt)

