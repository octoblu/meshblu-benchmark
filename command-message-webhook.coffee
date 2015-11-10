_         = require 'lodash'
commander = require 'commander'
async = require 'async'
colors = require 'colors'
MeshbluHttp = require 'meshblu-http'
MeshbluConfig = require 'meshblu-config'
debug     = require('debug')('meshblu-benchmark:message-webhook')
{Server}  = require 'http'
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

    @forwardCredentials = commander.credentials ? false

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

      callback(null, benchmark.elapsed())

  register: (callback) =>
    debug 'register'
    config = new MeshbluConfig().toJSON()
    meshbluHttp = new MeshbluHttp config
    meshbluHttp.register @deviceOptions(), (error, device) =>
      callback error, device

  message: (device, callback) =>
    debug 'message'
    config = new MeshbluConfig().toJSON()
    config.uuid  = device.uuid
    config.token = device.token

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
    listener = (request,response) =>
      response.end()
      console.log request.headers.date
      console.log request.headers.authorization
      @server.removeListener 'request', listener
      callback()

    @server.on 'request', listener


  deviceOptions: =>
    meshblu:
      messageHooks: [
        {
          url: "http://#{@host}:#{@port}/0"
          method: "GET"
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
