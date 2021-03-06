commander   = require 'commander'
packageJSON = require './package.json'

class Command
  run: =>
    commander
      .version packageJSON.version
      .command 'message-webhook', 'register webhook and benchmark round-trip'
      .command 'authenticate-blast', 'blast the authenticate service'
      .command 'subscription-list', 'benchmark the subscription list'
      .parse process.argv

    unless commander.runningCommand
      commander.outputHelp()
      process.exit 1

(new Command()).run()
