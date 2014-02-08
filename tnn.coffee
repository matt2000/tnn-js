# Implements Transparent Neural Networks (Strannegard 2012)
# @todo finish Imaginary actiovation. Run tests.coffee for current state.

_ = require 'underscore'
events = require 'events'

module.exports = tnn = {}

class tnn.Net
  `/*
    Stores global values, like the clock, and passes global messages to nodes.
  */`
  constructor: (debug_mode = false) ->
    @time = 1
    @nodes = []
    @debug_mode = debug_mode

  add: (node) ->
    # Wire up a new node to the net.
    @nodes.push(node)
    # Fill in missing reverse links on the targets. Redundant by design. @todo revisit
    n.addIn(node) for n in node.outgoing
    n.addOut(node) for n in node.incoming

  activate: (active = []) ->
    # Main Graph Update

    # Advance the clock
    @time += 1
    n.emit('tick') for n in @nodes
    # Update nodes with new value. The will in turn update their outgoing connections.
    for n in active
        n.update()
    # Update imaginary activations @todo - replace with event?
    #n.updateImag() for n in @nodes
    return @nodes

  tick: (dummy) ->
    # This is for test backward compatibility.
    @activate([])

  output: () ->
    console.log "==========================="
    console.log(n.log()) for n in @nodes


class tnn.BaseNode extends events.EventEmitter
  # Base class for all Node types/labels. Suitable for Sensor nodes.

  constructor: (net = NULL, outgoing = [], incoming = [], name = '') ->
    @net = @net || net
    @incoming = []
    @outgoing = []

    @addOut(n) for n in outgoing
    @addIn(n) for n in incoming

    @type = @type || 'Base'
    @name = @name || name || @type

    @p = 0.0
    @net.add(this)
    @threshold = @threshold || 0.5

    @r = 0.0 # Real Activation at current time
    @new = 0.0 #Real Activation at next time click
    @i = 0.0 # Imaginary Activation at current time
    @listen() #Attach listeners

  listen: ->
    #Event to update when incoming nodes change
    @on 'incomingUpdate', @update
    @on 'tick', ->
      @r = 0.0
    @on 'updateImag', @updateImag

  log: ->
    "#{@name}\t#{@type}\tr:#{@r}\ti:#{@i}"

  update: () ->
    @_real()
    @updateProb()
    n.emit('updateImag') for n in @incoming
    n.emit('incomingUpdate') for n in @outgoing


  getReal: ->
    return @r

  addIn: (node) ->
    # An incoming node has connected.
    if not (node in @incoming)
      @incoming.push(node)

  addOut: (node) ->
    # An outgoing node has connected.
    if not (node in @outgoing)
      @outgoing.push(node)

  activate: (debug = false) ->
    # @deprecated. For backward compatibility of tests.
    return @net.activate([this])

  _real: ->
    `/*
    Calculate the Real Activation for this node.
    The exact method is different for each sub-type.
    */`
    @r = 0.0
    if @incoming.length is 0 or _.find(@incoming, (n) -> n.r > @threshold)
      @r = 1.0
    return @r

  updateImag: ->
    `/*
    Calculate the Imaginary Activation for most nodes.
    Breaks from the Strannegard definition to allow multiple outgoing nodes.
    */`
    max = _.max(@outgoing, (n)-> n.i )
    @i = max.i

  updateProb: ->
    # Calculate the probability of Real Activation at time t + 1
    @p = (@getReal() + (@p * (@net.time - 1))) / @net.time


class tnn.AggregatorNode extends tnn.BaseNode
  `/*
    Base for Min, Max, and Average Nodes
  */`

  updateImag: () ->
    `/*
    Calculate the Imaginary Activation for aggregator node (Min, Max, Average). Per Definition 5.
    @todo Use Baye's Rule instead?
    */`
    vals = [1.0]
    vals.push(n.getReal() * n.p) for n in @incoming
    @i = _.min(vals)


class tnn.MinNode extends tnn.AggregatorNode
  type: 'Min'

  _real: ->
    #@todo Needs conversion.
    stimulation = [x.getReal() for x in @incoming]
    @r = min(stimulation)
    return @r


class tnn.MaxNode extends tnn.AggregatorNode
  type: 'Max'

  _real: ->
    @r = 0
    max = _.max @incoming, (n)-> n.getReal()
    @r = max.getReal()


class tnn.AverageNode extends tnn.AggregatorNode
  type: 'Avg'

  _real: ->
    sum = 0.0
    for x in @incoming
      sum += x.getReal()
    @r = (sum / @incoming.length)

class tnn.DelayNode extends tnn.BaseNode
  `/*
    Forwards its input after n time steps
  */`

  constructor: (net, n, outgoing = [], incoming = [], name = null) ->
    @delay = n
    @stored = []

    # Fill the storage with 0's to start
    c = 0
    while c < n
      c += 1
      @stored.push(0.0)

    @type = 'Delay:' +n
    super(net, outgoing, incoming, name)

  listen: ->
    @on 'incomingUpdate', @update
    @on 'updateImag', @updateImag
    @on 'tick', ->
      @r = @stored.shift()
      @update()

  _real: ->
    #Store highest Real Activation from incoming
    if @stored.length == @delay
      # We are calling this more than once in a discreet time step,
      # because we shift'd when the clock tick'd.
      test = @stored.pop()

    winner = _.max(@incoming, (n) -> n.getReal())
    @stored.push winner.getReal()

  log: ->
    l = "#{@name}\t#{@type}\tr:#{@r}\ti:#{@i}"
    for x in @stored
      x = 'und' if x == undefined
      l += " #{x},"
    return l


## Utilities ##

_.sum = (list) ->
  _.reduce list, (a,b) ->
    return a + b
