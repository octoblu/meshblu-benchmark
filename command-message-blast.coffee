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

class CommandMessageWebhook
  parseOptions: =>
    commander
      .option '-c, --cycles [n]', 'number of cycles to run (defaults to 10)', @parseInt, 10
      .option '-n, --number-of-messages [n]', 'Number of parallel messages per second (defaults to 1)', @parseInt, 1
      .parse process.argv

    {@numberOfMessages,@cycles} = commander

  run: =>
    @parseOptions()
    @elapsedTimes = []
    @startTimes = {}
    @currentCycle = 0

    console.log 'pid: ', process.pid
    process.on 'SIGINT', @printAverageAndDie
    process.on 'exit', @printAverageAndDie

    @registerReceiverAndSenders (error, receiver, senders) =>
      @die error if error?

      setInterval (=> @blast receiver, with: senders), 1000

  blast: (receiver, {with: senders}) =>
    return @printAverageAndDie() if @currentCycle >= @cycles
    @currentCycle += 1

    debug 'blast', @currentCycle, @cycles
    async.each senders, (sender, done) =>
      @message from: sender, to: receiver, done

  die: (error) =>
    if 'Error' == typeof error
      console.error colors.red error.message
    else
      console.error colors.red arguments...
    process.exit 1

  message: ({from: sender, to: receiver}, callback) =>
    messageId = uuid.v1()

    message =
      devices: [receiver.uuid]
      payload:
        messageId: messageId

    @startTimes[messageId] = Date.now()

    meshbluConfig = new MeshbluConfig
    config = _.extend meshbluConfig.toJSON(), _.pick(sender, 'uuid', 'token')

    meshbluHttp = new MeshbluHttp config
    meshbluHttp.message message, callback

  parseInt: (str) =>
    parseInt str

  onMessage: (message) =>
    endTime = Date.now()
    messageId = message?.payload?.messageId
    return unless messageId?

    startTime = @startTimes[messageId]
    delete @startTimes[messageId]

    # startTime = message.payload.startTime
    return unless startTime?

    elapsedTime = endTime - startTime
    @elapsedTimes.push elapsedTime

    # debug "onMessage", elapsedTime: elapsedTime

  printAverageAndDie: =>
    average = _.sum(@elapsedTimes) / _.size(@elapsedTimes)
    debug
      averageElapsedTime: average
      danglingMessages: _.size(_.keys(@startTimes))
      successfulRoundTrips: _.size(@elapsedTimes)
      percentile90: @nthPercentile(90, @elapsedTimes)
      median: @nthPercentile(50, @elapsedTimes)
    process.exit 0

  register: (callback) =>
    benchmark = new Benchmark label: 'register'
    meshbluConfig = new MeshbluConfig
    meshbluHttp = new MeshbluHttp meshbluConfig.toJSON()
    meshbluHttp.register {}, callback

  registerReceiverAndSenders: (callback) =>
    async.parallel {
      receiver: @registerReceiver
      senders: @registerSenders
    }, (error, results={}) =>
      {receiver,senders} = results
      callback error, receiver, senders

  registerReceiver: (callback) =>
    async.waterfall [
      @register
      @subscribeToDevice
    ], callback

  registerSenders: (callback) =>
    async.timesLimit @numberOfMessages, 50, @registerSender, callback

  registerSender: (i, callback) =>
    @register callback

  singleRun: (device, callback) =>
    benchmark = new Benchmark label: 'message-webhook'

    async.parallel [
      @listenForMessage
      async.apply @message, device
    ], (error) =>
      return callback error if error?

      console.log benchmark.toString()
      callback(null, benchmark.elapsed())

  subscribeToDevice: (device, callback) =>
    meshbluConfig = new MeshbluConfig
    config = _.extend meshbluConfig.toJSON(), _.pick(device, 'uuid', 'token')
    conn = new MeshbluWebsocket config
    conn.connect (error) =>
      debug 'subscribeToDevice', error
      return callback error if error?
      conn.on 'message', @onMessage
      callback error, device

  nthPercentile: (percentile, array) =>
    array = _.sortBy array
    index = (percentile / 100) * _.size(array)
    if Math.floor(index) == index
      return (array[index-1] + array[index]) / 2

    return array[Math.floor index]

new CommandMessageWebhook().run()
