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
      .option '-n, --number-of-messages [n]', 'Number of parallel messages per second (defaults to 1)', @parseInt, 1
      .parse process.argv

    {@numberOfMessages} = commander

  run: =>
    console.log 'pid: ', process.pid
    process.on 'SIGINT', @printAverageAndDie
    process.on 'exit', @printAverageAndDie
    setInterval @blast, 1000
    @parseOptions()
    @elapsedTimes = []
    @startTimes = {}

  blast: =>
    async.times @numberOfMessages, (i, done)=>
      messageId = uuid.v1()
      startTime = Date.now()
      @startTimes[messageId] = startTime

      request.get 'http://localhost:3000/status', (error) =>
        return done error if error?
        delete @startTimes[messageId]
        endTime = Date.now() - startTime
        @elapsedTimes.push endTime

  die: (error) =>
    if 'Error' == typeof error
      console.error colors.red error.message
    else
      console.error colors.red arguments...
    process.exit 1

  parseInt: (str) =>
    parseInt str

  printAverageAndDie: =>
    average = _.sum(@elapsedTimes) / _.size(@elapsedTimes)
    debug
      averageElapsedTime: average
      danglingMessages: _.size(_.keys(@startTimes))
      successfulRoundTrips: _.size(@elapsedTimes)
      percentile90: @nthPercentile(90, @elapsedTimes)
      median: @nthPercentile(50, @elapsedTimes)
    process.exit 0

  nthPercentile: (percentile, array) =>
    array = _.sortBy array
    index = (percentile / 100) * _.size(array)
    if Math.floor(index) == index
      return (array[index-1] + array[index]) / 2

    return array[Math.floor index]

new CommandMassHealthcheck().run()
