#
#Name:         tlt
#Description:  TLT GPS server for Node.js
#Source:       https://github.com/korzhyk/nodejs-tlt
#Feedback:     https://github.com/korzhyk/nodejs-tlt/issues
#License:      Unlicense / Public Domain
#
#This is free and unencumbered software released into the public domain.
#
#Anyone is free to copy, modify, publish, use, compile, sell, or
#distribute this software, either in source code form or as a compiled
#binary, for any purpose, commercial or non-commercial, and by any
#means.
#
#In jurisdictions that recognize copyright laws, the author or authors
#of this software dedicate any and all copyright interest in the
#software to the public domain. We make this dedication for the benefit
#of the public at large and to the detriment of our heirs and
#successors. We intend this dedication to be an overt act of
#relinquishment in perpetuity of all present and future rights to this
#software under copyright law.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
#OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
#ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#OTHER DEALINGS IN THE SOFTWARE.
#
#For more information, please refer to <http://unlicense.org>
#

# INIT
redis        = require "redis"
net          = require "net"
EventEmitter = require("events").EventEmitter
_            = require "lodash"
tlt          = new EventEmitter()

# defaults
tlt.settings =
  ip: "0.0.0.0" # default listen on all IPs
  port: 0 # 0 = random, 'listening' event reports port
  connections: 10 # 10 simultaneous connections
  timeout: 10 # 10 seconds idle timeout


# Create server
tlt.createServer = (vars) ->
  
  # override settings
  if typeof vars is "object" and Object.keys(vars).length >= 1
    for key of vars
      tlt.settings[key] = vars[key]
  
  # start server
  
  # socket idle timeout
  tlt.server = net.createServer((socket) ->
    if tlt.settings.timeout > 0
      socket.setTimeout tlt.settings.timeout * 1000, ->
        tlt.emit "timeout", socket
        socket.end()

  ).listen(tlt.settings.port, tlt.settings.ip, ->
    
    # server ready
    tlt.emit "listening", tlt.server.address()
  )
  
  # maximum number of slots
  tlt.server.maxConnections = tlt.settings.connections
  
  # inbound connection
  tlt.server.on "connection", (socket) ->
    tlt.emit "connection", socket
    socket.setEncoding "utf8"
    data = ""
    
    # receiving data
    socket.on "data", (chunk) ->
      tlt.emit "data", chunk
      data += chunk

    
    # complete
    socket.on "close", ->
      tlt.emit "close", socket
      gps = tlt.parse(data)
      if gps
        tlt.emit "track", gps
      else
        tlt.emit "fail",
          reason: "Cannot parse GPS data from device"
          socket: socket
          input: data


# Parse GPRMC string
#
#   #357671030584277#V500#0000#ANSWER#1
#   #374d05d3$GPRMC,220912.000,A,5036.5419,N,02616.3000,E,0.04,359.38,150513,,,A*6E
#   ##
#

tlt.parse = (raw) ->
  parsePoint = (point)->
    s = point.split(',')

    currentYear = new Date().getUTCFullYear() + ""

    time = s[1].replace /(.{1,2})(.{1,2})(.{1,2})/, (match, hour, minutes, seconds)-> "#{hour}:#{minutes}:#{seconds}"
    date = s[9].replace /(.{1,2})(.{1,2})(.{1,2})/, (match, day, month, year)-> "#{currentYear.slice(0,2)}#{year}-#{month}-#{day}"
    datetime = "#{date}T#{time}Z"

    type: 'Feature'
    geometry:
      type: "Point"#Latitude                Longitude
      coordinates: [tlt.fixGeo(s[5], s[6]), tlt.fixGeo(s[3], s[4])]
    properties:
      speed: parseFloat(s[7]) * 1.852 # From knots to kph
      direction: parseFloat(s[8])
      date: datetime

  parseBlock = (block)->
    b = {}

    block = block.replace /#([0-9]{15})#(\w+)#(\d+)#(\w+)#(\d+)#/, (match, imei, name, password, status, quantity)->
      b.uid = imei
      b.name = name
      b.password = password
      b.status = status
      b.quantity = parseInt(quantity, 10)
      ""
    b.data = []
    b.data.push parsePoint(p) for p in block.split('#')

    b # Return parsed block

  blocks = raw.replace(/[\r\n ]/g, '') # Replace new lines
              .trim()                 # Trim string
              .split('##')            # And split in to blocks

  blocks.pop()                        # Remove last block coz not complete or empty
  
  parseBlock(b) for b in blocks


# Clean geo positions, with 6 decimals
tlt.fixGeo = (one, two) ->
  minutes = one.substr(-7, 7)
  degrees = parseInt(one.replace(minutes, ""), 10)
  one = degrees + (minutes / 60)
  one = parseFloat(((if two is "S" or two is "W" then "-" else "")) + one)
  Math.round(one * 1000000) / 1000000



# Start Server
# Setup Redis client
client = redis.createClient()
            .on "error", (msg)-> console.log "Redis: %s", msg
# ready
port = 10028
server = tlt


server.createServer
  port: port

server.on "listening", (srv)-> console.log "Starting %s server TLT on %s:%s", srv.family, srv.address, srv.port

server.on "connection", (socket)-> console.log "New connection from: %s", socket.remoteAddress
server.on "close", (socket)-> console.log "Connection %s closed!", socket._peername?.address or null

server.on "track", (blocks)->
  client.publish "incoming:block", JSON.stringify(block) for block in blocks
