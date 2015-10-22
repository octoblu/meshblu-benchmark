_         = require 'lodash'
commander = require 'commander'
async = require 'async'
uuid = require 'uuid'
colors = require 'colors'
MeshbluHttp = require 'meshblu-http'
MeshbluConfig = require 'meshblu-config'
debug     = require('debug')('meshblu-benchmark:message-blast')
MeshbluWebsocket = require 'meshblu-websocket'
Benchmark = require 'simple-benchmark'
request = require 'request'

class CommandMassHealthcheck
  parseOptions: =>
    commander
      .option '-c, --cycles [n]', 'number of cycles to run (defaults to 10)', @parseInt, 10
      .option '-n, --number-of-messages [n]', 'Number of parallel messages per second (defaults to 1)', @parseInt, 1
      .option '-m, --method [method]', 'Type of method to use (defaults to get)', 'get'
      .parse process.argv

    {@cycles,@numberOfMessages,@method} = commander

  run: =>
    @currentCycle = 0
    console.log 'pid: ', process.pid
    setInterval @blast, 1000
    @parseOptions()
    @elapsedTimes = []
    @startTimes = {}

  blast: =>
    return @printAverageAndDie() if @currentCycle >= @cycles
    # _.defer => debug 'blast', @currentCycle
    @currentCycle += 1
    async.times @numberOfMessages, (i, done) =>
      _.delay =>
        messageId = uuid.v1()
        startTime = Date.now()
        @startTimes[messageId] = startTime

        body =
          devices: ['ae2d0b34-4299-4c96-b6d3-4df0012f4325']
          payload:
            messageId: 'ca6a5de1-a023-46e7-8846-b43e73f74cfd'
            times:
              start: Date.now()

        request[@method] 'http://localhost:3000/status', json: body, (error) =>
          return done error if error?
          delete @startTimes[messageId]
          endTime = Date.now() - startTime
          @elapsedTimes.push endTime
      , _.random(0, 50)

  die: (error) =>
    if 'Error' == typeof error
      console.error colors.red error.message
    else
      console.error colors.red arguments...
    process.exit 1

  parseInt: (str) =>
    parseInt str

  printAverageAndDie: =>
    setTimeout =>
      average = _.sum(@elapsedTimes) / _.size(@elapsedTimes)
      console.log JSON.stringify
        averageElapsedTime: average
        danglingMessages: _.size(_.keys(@startTimes))
        successfulRoundTrips: _.size(@elapsedTimes)
        percentile90: @nthPercentile(90, @elapsedTimes)
        median: @nthPercentile(50, @elapsedTimes)
      , null, 2
      process.exit 0
    , 2000

  nthPercentile: (percentile, array) =>
    array = _.sortBy array
    index = (percentile / 100) * _.size(array)
    if Math.floor(index) == index
      return (array[index-1] + array[index]) / 2

    return array[Math.floor index]

new CommandMassHealthcheck().run()
