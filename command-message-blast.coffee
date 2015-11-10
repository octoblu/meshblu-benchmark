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
      .option '-t, --type [type]', 'Type of connection to use (defaults to http)', 'http'
      .parse process.argv

    {@numberOfMessages,@cycles,@type} = commander

  run: =>
    @registeredDevices = []
    @parseOptions()
    @elapsedTimes = []
    @startTimes = {}
    @messages = []
    @currentCycle = 0

    console.log 'pid: ', process.pid

    @registerReceiverAndSenders (error, receiver, senders) =>
      @die error if error?

      setInterval (=> @blast receiver, with: senders), 1000

  averageTimeBetween: (times, begin, end) =>
    differences = _.map times, (time) => time[end] - time[begin]
    _.sum(differences) / _.size(differences)

  blast: (receiver, {with: senders}) =>
    return @printAverageAndDie() if @currentCycle >= @cycles
    @currentCycle += 1

    # _.defer => debug 'blast', @currentCycle, @cycles
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
      topic: 'make peter happy'
      payload:
        messageId: messageId
        times:
          start: Date.now()

    @startTimes[messageId] = message.payload.times.start

    @["#{@type}Message"] from: sender, to: receiver, message

  httpMessage: ({from: sender, to: receiver}, message) =>
    start = message.payload.times.start
    sender.message message #, =>

  websocketMessage: ({from: sender, to: receiver}, message) =>
    receiver.message message

  parseInt: (str) => parseInt str

  onMessage: (message) =>
    endTime = Date.now()
    messageId = message?.payload?.messageId
    return unless messageId?

    @receivedMessages ?= {}
    @receivedMessages[messageId] ?= 0
    @receivedMessages[messageId] += 1

    startTime = @startTimes[messageId]
    delete @startTimes[messageId]

    # startTime = message.payload.startTime
    return unless startTime?
    elapsedTime = endTime - startTime
    @elapsedTimes.push elapsedTime

    message.payload.times.end = endTime
    @messages.push message.payload.times

    # debug "onMessage", elapsedTime: elapsedTime

  printAverageAndDie: =>
    setTimeout =>
      average = _.sum(@elapsedTimes) / _.size(@elapsedTimes)
      debug
        averageElapsedTime: average
        danglingMessages: _.size(_.keys(@startTimes))
        successfulRoundTrips: _.size(@elapsedTimes)
        percentile90: @nthPercentile(90, @elapsedTimes)
        median: @nthPercentile(50, @elapsedTimes)
        averageRoutedToEnd: @averageTimeBetween @messages, 'routed', 'end'
        averageParseStartToEnd: @averageTimeBetween @messages, 'parseStart', 'end'

      async.each @registeredDevices, @unregister, =>
        @registeredDevices = []
        process.exit 0
    , 2000

  register: (callback) =>
    meshbluConfig = new MeshbluConfig
    meshbluHttp = new MeshbluHttp meshbluConfig.toJSON()
    meshbluHttp.register {}, (error, device) =>
      return callback error if error?
      @registeredDevices.push device
      callback null, device

  unregister: (device, callback) =>
    meshbluConfig = new MeshbluConfig
    meshbluHttp = new MeshbluHttp meshbluConfig.toJSON()
    meshbluHttp.unregister device, callback

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
    @register (error, device) =>
      meshbluConfig = new MeshbluConfig
      config = _.extend meshbluConfig.toJSON(), _.pick(device, 'uuid', 'token')

      # sender = new MeshbluWebsocket config
      # sender.connect (error) =>
      #   callback error, sender
      config =
        uuid: 'c780403c-6b43-46be-9357-728d476f84c7'
        token: '1979780f49d488f41293f70ff1baec9be910cf9b'
        server: 'localhost'
        port: '6000'
        protocol: 'http'

      sender = new MeshbluHttp config
      callback error, sender
      # callback error, config

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
    config = meshbluConfig.toJSON()
    # config.uuid  = device.uuid
    # config.token = device.token
    config =
      uuid: '7a9f8f80-4712-47be-a100-f0579836a9b9'
      token: 'cdbc4fa219d40088b3189b66af27e051a8fa358e'
      hostname: 'localhost'
      port: '3000'
      protocol: 'http'

    conn = new MeshbluWebsocket config
    conn.connect (error) =>
      return callback error if error?
      conn.on 'message', @onMessage
      # conn.uuid = device.uuid
      conn.uuid = config.uuid
      callback error, conn

  nthPercentile: (percentile, array) =>
    array = _.sortBy array
    index = (percentile / 100) * _.size(array)
    if Math.floor(index) == index
      return (array[index-1] + array[index]) / 2

    return array[Math.floor index]

new CommandMessageWebhook().run()
