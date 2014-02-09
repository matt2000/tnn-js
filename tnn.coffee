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
    # Update nodes with new value. The will in turn update their outgoing connections.
    n.emit('incomingUpdate') for n in active
    @time += 1
    # Hacky debug output. @todo revise
    if _.find(@nodes, (n) -> n.debug)
      console.log "\nAfter update of " + active[0].name
      @output()
    n.emit('tick') for n in @nodes
    return @nodes

  tick: (callback = ->) ->
    # This is mainly for test backward compatibility.
    @activate()
    callback()

  output: () ->
    console.log "==========================="
    console.log(n.log()) for n in @nodes


class tnn.BaseNode extends events.EventEmitter
  # Base class for all Node types/labels. Suitable for Sensor nodes.

  constructor: (net, outgoing = [], incoming = [], name = '') ->
    # We use `@prop || prop` in case this is called by child constructors.
    @net = @net || net
    @incoming = []
    @outgoing = []

    @addOut(n) for n in outgoing
    @addIn(n) for n in incoming

    # @type is a unique, Human Readable label for the Node's class.
    @type = @type || 'Base'
    # @name is a Human-readable label for the particular Node.
    @name = @name || name || @type

    @p = 0.0
    @net.add(this)
    @threshold = @threshold || 0.5

    @r = 0.0 # Real Activation at current time
    @lastReal = 0.0 #Real Activation at last time click
    @i = 0.0 # Imaginary Activation at current time
    @listen() #Attach listeners

  listen: ->
    #Event to update when incoming nodes change
    @on 'incomingUpdate', @update
    @on 'tick', @tick
    @on 'updateImag', @updateImag


  # These are things this node needs to do on every time step, even if it is
  # not "active".
  tick: ->
    @debug = false
    @lastReal = @r
    @r = 0.0

  # A String representation of the node state
  log: ->
    p = @p.toString().substr(0,4)
    "#{@name}\t#{@type}\tr:#{@r}\tp:#{p}\ti:#{@i}"

  # Calculate the current Real activation of this node. This is a separate
  # method from 'tick' because we might be able to skip it to save computations,
  # or it may be called multiple times within a discreet time step.
  update: () ->
    @updateReal()
    @updateProb()
    @updateImag()
    n.emit('updateImag') for n in @incoming
    n.emit('incomingUpdate') for n in @outgoing


  getReal: ->
    return @r

  getLastReal: ->
    return @lastReal

  addIn: (node) ->
    # An incoming node has connected.
    if not (node in @incoming)
      @incoming.push(node)

  addOut: (node) ->
    # An outgoing node has connected.
    if not (node in @outgoing)
      @outgoing.push(node)

  activate: (debug = false)->
    @r = 1.0
    @debug = debug
    return @net.activate([this])

  updateReal: (callback = ->) ->
    `/*
    Calculate the Real Activation for this node.
    The exact calculation is usually different for each sub-type.
    */`
    if @incoming.length is 0 or _.find(@incoming, (n) => n.r > @threshold)
      @r = 1.0
    callback()
    return @r

  updateImag: (callback = ->) ->
    `/*
    Calculate the Imaginary Activation for most nodes.
    We break from the Strannegard (2012) definition to allow multiple outgoing nodes, akin to (2013).
    */`
    max = _.max(@outgoing, (n)-> n.i )
    @i = max.i
    #console.log(@name +': Update Imag')
    callback()

  updateProb: ->
    # Calculate the probability of Real Activation at time t + 1
    @p += (@getReal() - @p) / @net.time


class tnn.AggregatorNode extends tnn.BaseNode
  `/*
    Base for Min, Max, and Average Nodes
  */`

  updateImag: (callback = ->) ->
    `/*
    Calculate the Imaginary Activation for aggregator node (Min, Max, Average). Per Definition 5.
    @todo Use Bayes Rule instead?
    */`
    vals = []
    vals.push(n.getReal() * n.p) for n in @incoming
    @i = _.min([1.0, _.sum(vals)])
    callback()


class tnn.MinNode extends tnn.AggregatorNode
  type: 'Min'

  updateReal: (callback = ->) ->
    #@todo Needs conversion.
    stimulation = [x.getReal() for x in @incoming]
    @r = min(stimulation)
    callback()
    return @r


class tnn.MaxNode extends tnn.AggregatorNode
  type: 'Max'

  updateReal: (callback = ->) ->
    max = _.max @incoming, (n)-> n.getReal()
    @r = max.getReal() || 0
    callback()


class tnn.AverageNode extends tnn.AggregatorNode
  type: 'Avg'

  updateReal: (callback = ->) ->
    @r = (_.sum(_.pluck(@incoming, 'r')) / @incoming.length)
    callback()

class tnn.DelayNode extends tnn.BaseNode
  `/*
    Forwards its input after n time steps
  */`

  constructor: (net, n, outgoing = [], incoming = [], name = null) ->
    @delay = n
    @stored = []

    # Fill the storage with 0's to start
    while @stored.length < @delay
      @stored.push(0.0)

    @type = 'Delay:' +n
    super(net, outgoing, incoming, name)


  tick: ->
      @r = @stored.shift()
      @update()

  updateReal: ->
    #Store highest Real Activation from incoming
    if @stored.length == @delay
      # We are calling this more than once in a discreet time step,
      # because we shift'd when the clock tick'd.
      test = @stored.pop()

    winner = _.max(@incoming, (n) -> n.getReal())
    @stored.push winner.getReal()

  log: ->
    l = super()
    for x in @stored
      x = 'und' if x == undefined
      l += " #{x},"
    return l


## Utilities ##

_.sum = (list) ->
  _.reduce list, (a,b) ->
    return a + b

_.any = (list, iterator = _.identity) ->
  _.find(list, iterator)
