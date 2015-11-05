_             = require 'lodash'
commander     = require 'commander'
async         = require 'async'
uuid          = require 'uuid'
colors        = require 'colors'
MeshbluConfig = require 'meshblu-config'
debug         = require('debug')('meshblu-benchmark:subscription-list')
Benchmark     = require 'simple-benchmark'
request       = require 'request'
url           = require 'url'
Table         = require 'cli-table'

class CommandSubscriptionList
  parseOptions: =>
    commander
      .option '-c, --cycles [n]', 'number of cycles to run (defaults to 10)', @parseInt, 10
      .option '-n, --number-of-messages [n]', 'Number of parallel messages per second (defaults to 1)', @parseInt, 1
      .parse process.argv

    {@numberOfMessages,@cycles} = commander

  run: =>
    @parseOptions()

    @statusCodes = []
    @elapsedTimes = []
    @benchmark = new Benchmark label: 'overall'

    async.timesSeries @cycles, @cycle, @printResults

  getSubscriptions: (i, callback) =>
    meshbluConfig = new MeshbluConfig
    {hostname,port,uuid,token} = meshbluConfig.toJSON()

    uri = url.format
      protocol: 'http'
      hostname: hostname
      port: port
      pathname: "/devices/#{uuid}/subscriptions"

    requestOption =
      url: uri
      method: 'GET'
      auth:
        username: uuid
        password: token

    benchmark = new Benchmark label: 'authenticate'
    request requestOption, (error, response) =>
      if error?
        console.error error.message
        return

      @elapsedTimes.push benchmark.elapsed()
      @statusCodes.push response.statusCode
      callback()

  cycle: (i, callback) =>
    async.times @numberOfMessages, @getSubscriptions, callback

  die: (error) =>
    if 'Error' == typeof error
      console.error colors.red error.message
    else
      console.error colors.red arguments...
    process.exit 1

  parseInt: (str) => parseInt str

  printResults: (error) =>
    return @die error if error?
    elapsedTime = @benchmark.elapsed()
    averagePerSecond = (_.size @statusCodes) / (elapsedTime / 1000)
    messageLoss = 1 - (_.size(@statusCodes) / (@cycles * @numberOfMessages))

    generalTable = new Table
    generalTable.push
      'took'                 : "#{elapsedTime}ms"
    ,
      'average per second'   : "#{averagePerSecond}/s"
    ,
      'received status codes': "#{_.uniq @statusCodes}"
    ,
      'message loss'         : "#{messageLoss * 100}%"

    percentileTable = new Table
      head: ['10th', '25th', '50th', '75th', '90th']

    percentileTable.push [
      @nthPercentile(10, @elapsedTimes)
      @nthPercentile(25, @elapsedTimes)
      @nthPercentile(50, @elapsedTimes)
      @nthPercentile(75, @elapsedTimes)
      @nthPercentile(90, @elapsedTimes)
    ]

    console.log "\n\nResults:\n"
    console.log generalTable.toString()
    console.log percentileTable.toString()

    process.exit 0

  nthPercentile: (percentile, array) =>
    array = _.sortBy array
    index = (percentile / 100) * _.size(array)
    if Math.floor(index) == index
      return (array[index-1] + array[index]) / 2

    return array[Math.floor index]

new CommandSubscriptionList().run()
