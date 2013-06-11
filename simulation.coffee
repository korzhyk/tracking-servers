

redis  = require "redis"
fs = require 'fs'
_      = require "lodash"
moment = require 'moment'

env      = process.env.NODE_ENV or 'development'
# Configure
config = require("../cli/config/environment")[env]

console.log "Connecting to %s at %s:%s", 'Redis', config.redis.host, config.redis.port
rd_pub = redis.createClient()
  .on 'error', (msg)-> console.log "Redis PUB: %s".error, msg


points = require './points'
total_points = points.length

getPoint = (curr) ->
  curr = 0 if curr > total_points
  point = points[curr]
  new LatLon(point[0], point[1])

###
Creates a point on the earth's surface at the supplied latitude / longitude

@constructor
@param {Number} lat: latitude in numeric degrees
@param {Number} lon: longitude in numeric degrees
@param {Number} [rad=6371]: radius of earth if different value is required from standard 6,371km
###
LatLon = (lat, lon, rad) ->
  rad = 6371  if typeof (rad) is "undefined" # earth's mean radius in km
  # only accept numbers or valid numeric strings
  @_lat = (if typeof (lat) is "number" then lat else (if typeof (lat) is "string" and lat.trim() isnt "" then +lat else NaN))
  @_lon = (if typeof (lon) is "number" then lon else (if typeof (lon) is "string" and lon.trim() isnt "" then +lon else NaN))
  @_radius = (if typeof (rad) is "number" then rad else (if typeof (rad) is "string" and trim(lon) isnt "" then +rad else NaN))

###
Returns the distance from this point to the supplied point, in km
(using Haversine formula)

from: Haversine formula - R. W. Sinnott, "Virtues of the Haversine",
Sky and Telescope, vol 68, no 2, 1984

@param   {LatLon} point: Latitude/longitude of destination point
@param   {Number} [precision=4]: no of significant digits to use for returned value
@returns {Number} Distance in km between this point and destination point
###
LatLon::distanceTo = (point, precision) ->

  # default 4 sig figs reflects typical 0.3% accuracy of spherical model
  precision = 4  if typeof precision is "undefined"
  R = @_radius
  lat1 = @_lat.toRad()
  lon1 = @_lon.toRad()
  lat2 = point._lat.toRad()
  lon2 = point._lon.toRad()
  dLat = lat2 - lat1
  dLon = lon2 - lon1
  a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  R / 1000 * c


###
Returns the (initial) bearing from this point to the supplied point, in degrees
see http://williams.best.vwh.net/avform.htm#Crs

@param   {LatLon} point: Latitude/longitude of destination point
@returns {Number} Initial bearing in degrees from North
###
LatLon::bearingTo = (point) ->
  lat1 = @_lat.toRad()
  lat2 = point._lat.toRad()
  dLon = (point._lon - @_lon).toRad()
  y = Math.sin(dLon) * Math.cos(lat2)
  x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon)
  brng = Math.atan2(y, x)
  (brng.toDeg() + 360) % 360

if typeof (Number::toRad) is "undefined"
  Number::toRad = ->
    this * Math.PI / 180

if typeof (Number::toDeg) is "undefined"
  Number::toDeg = ->
    180 / this * Math.PI

send = (p, id) ->
  id++
  point = getPoint(p)
  point_next = getPoint(p+1)
  uid: "test#{id}"
  name: "Tracker #{id}"
  password: 'Password'
  status: 'AUTO'
  quantity: 1
  fake: true
  data: [
    type: 'Feature'
    geometry:
      type: "Point"#Latitude                Longitude
      coordinates: [point._lat, point._lon]
    properties:
      speed: point.distanceTo(point_next)
      direction: point.bearingTo(point_next)
      date: moment().toDate()
  ]

t = [100, 200, 300, 400, 500, 600, 700]

setInterval(->
  t.forEach (val, i)->
    rd_pub.publish "incoming:block", JSON.stringify(send val, i)
    t[i]++
    t[i] = 0 if val > total_points
, 2000
)

