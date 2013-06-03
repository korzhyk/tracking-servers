require '../cli/config/extends'

redis  = require "redis"
pg     = require "pg"
fs = require 'fs'
_      = require "lodash"
mongoose = require 'mongoose'
moment = require 'moment'
colors = require '../cli/config/colors'

env      = process.env.NODE_ENV or 'development'
# Configure
config = require("../cli/config/environment")[env]
# Bootstrap mongodb database
console.log "Connecting to %s at %s", 'MongoDB'.info, config.mongodb.debug
mongoose.connect(config.mongodb)
mongoose.connection.on 'error', (msg)-> console.log "Mongoose: %s".error, msg.to_s.error
Tracker = mongoose.model "Tracker", require '../cli/app/models/tracker'
# Bootstrap redis database
console.log "Connecting to %s at %s:%s", 'Redis'.info, config.redis.host.debug, config.redis.port.to_s.debug
rd_sub = redis.createClient()
            .on 'error', (msg)-> console.log "Redis SUB: %s".error, msg.to_s.error

rd_pub = redis.createClient()
            .on 'error', (msg)-> console.log "Redis PUB: %s".error, msg.to_s.error

# Bootstrap PostGIS database
console.log "Connecting to %s at %s", 'PostGIS'.info, config.postgres.debug
pg_client = new pg.Client(config.postgres)
pg_client.connect (msg)-> console.log "Postgres: %s", msg.to_s.error if msg



# Listen for new points
rd_sub.subscribe('incoming:block')
rd_sub.on 'message', (chanel, block)->
  return unless block
  savePoint JSON.parse(block)


console.log "Storage server is running and wait for points!"


savePoint = (block)->
  Tracker.findOne(uid: block.uid).lean().exec (err, tracker)->
    
    console.log "New data from %s, with %d point(s).", tracker.name, block.quantity

    live = []

    for feature in block.data


      feature.properties.status = block.status
      feature.properties.tracker_id = tracker._id
      feature.properties.date = moment.utc(feature.properties.date).toJSON()
      live.push feature

      feature.properties.geom = feature.geometry
      columns = _.keys(feature.properties)

      preparedReplaces = ->
        res = for i of columns
          i++
          "$#{i}"
        res.join(',')

      preparedValues = ->
        for key in columns
          val = feature.properties[key]
          type = typeof val
          switch type
            when 'object'
              if val.type is 'Point' then "ST_SetSRID(ST_GeomFromGeoJSON('#{JSON.stringify(val)}'), 4326)" else "'#{val}'"
            when 'string'
              "'#{val}'"
            else val

      q =  "
INSERT INTO points(#{columns.join(',')}) VALUES(#{preparedValues().join(',')})
"
      pg_client.query q


    rd_pub.publish 'live:point', JSON.stringify
      tracker_id: tracker._id
      data: live
