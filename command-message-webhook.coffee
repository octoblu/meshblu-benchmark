_         = require 'lodash'
commander = require 'commander'
async = require 'async'
colors = require 'colors'
MeshbluHttp = require 'meshblu-http'
MeshbluConfig = require 'meshblu-config'
debug     = require('debug')('meshblu-benchmark:message-webhook')
{Server}  = require 'net'
Benchmark = require './src/benchmark'

class CommandMessageWebhook
  parseOptions: =>
    commander
      .option '-h, --host [host]', 'host to register webhook for (defaults localhost)', 'localhost'
      .option '-p, --port [port]', 'Port to bind to / register webhook for (defaults :9000)', '9000'
      .option '-c, --credentials', 'Enable forwarding meshblu credentials'
      .option '-n, --number-of-times [n]', 'Run benchmark numerous times (defaults to 1)', @parseInt, 1
      .parse process.argv

    {@host,@port,@numberOfTimes} = commander

    @forwardCredentials = commander.forwardCredentials ? false

  parseInt: (str) =>
    parseInt str

  run: =>
    @parseOptions()

    @register (error, device) =>
      return @die error if error?

      @startServer (error) =>
        return callback error if error?

        async.mapSeries _.times(@numberOfTimes), (n, done) =>
          @singleRun device, done
        , (error, results) =>
          return @die error if error?
          average = _.sum(results) / results.length
          console.log "average: #{average}ms"
          process.exit 0

  singleRun: (device, callback) =>
    benchmark = new Benchmark label: 'message-webhook'


    async.parallel [
      @listenForMessage
      async.apply @message, device
    ], (error) =>
      return callback error if error?

      console.log benchmark.toString()
      callback(null, benchmark.elapsed())

  register: (callback) =>
    debug 'register'
    config = new MeshbluConfig
    meshbluHttp = new MeshbluHttp config.toJSON()
    meshbluHttp.register @deviceOptions(), (error, device) =>
      callback error, device

  message: (device, callback) =>
    debug 'message'
    meshbluConfig = new MeshbluConfig
    config = _.extend meshbluConfig.toJSON(), _.pick(device, 'uuid', 'token')

    meshbluHttp = new MeshbluHttp config
    meshbluHttp.message devices: [device.uuid], callback

  startServer: (callback) =>
    debug 'startServer'
    @server = new Server
    @server.listen @port, callback

  stopServer: (callback) =>
    debug 'stopServer'
    @server.close callback

  listenForMessage: (callback) =>
    debug 'listenForMessage'
    listener = (socket) =>
      buffer = new Buffer(0)

      socket.on 'readable', =>
        while data = socket.read()
          buffer = Buffer.concat [buffer, data]
        socket.end()
        @server.removeListener 'connection', listener

      socket.on 'error', callback
      socket.on 'end',   callback

    @server.on 'connection', listener

  deviceOptions: =>
    meshblu:
      messageHooks: [
        {
          url: "http://#{@host}:#{@port}"
          method: "POST"
          generateAndForwardMeshbluCredentials: @forwardCredentials
        }
      ]

  die: (error) =>
    if 'Error' == typeof error
      console.error colors.red error.message
    else
      console.error colors.red arguments...
    process.exit 1

new CommandMessageWebhook().run()
