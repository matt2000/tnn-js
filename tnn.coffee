# Implements Transparent Neural Networks (Strannegard 2012)
# @todo finish Imaginary actiovation. Run tests.coffee for current state.


_ = require 'underscore'
events = require 'events'

module.exports = tnn = {}

class tnn.Net
  `/*
    Stores global values, like the clock, and passes global messages to nodes.
  */`
  constructor: (@debug_mode = false) ->
    @time = 1
    @nodes = []

  add: (node) ->
    # Wire up a new node to the net.
    @nodes.push(node)
    # Fill in missing reverse links on the targets. Redundant by design. @todo revisit
    n.addIn(node) for n in node.outgoing
    n.addOut(node) for n in node.incoming

  activate: (active = []) ->
    # Main Graph Update
    # Update nodes with new value. They will in turn update their outgoing connections.
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
  # Use @emit('method') to call methods that shoudl propogate updates ot connected nodes.
  # Calling the method directly is possible, but not normally desirable.


  constructor: (@net, outgoing = [], incoming = [], name = '') ->
    @incoming = []
    @outgoing = []

    @addOut(n) for n in outgoing
    @addIn(n) for n in incoming

    # @type is a unique, Human Readable label for the Node's class.
    @type = @type || 'Base'
    # @name is a Human-readable label for the particular Node.
    # We use `@prop || prop` in case this is called by child constructors.
    @name = @name || name || @type

    @p = 0.0
    @lastProb = 0.0
    @net.add(this)
    @threshold = @threshold || 0.5

    @r = 0.0 # Real Activation at current time
    @lastReal = 0.0 #Real Activation at last time click
    @i = 0.0 # Imaginary Activation at current time
    @listen() #Attach listeners

  listen: ->
    #Event to update when incoming nodes change
    @on 'incomingUpdate', ->
      @update()
      n.emit('incomingUpdate') for n in @outgoing
    @on 'tick', @tick
    @on 'updateImag', ->
      @updateImag()
      # Always propgate Imaginary Activation updates.
      n.emit('updateImag') for n in @incoming


  # These are things this node needs to do on every time step, even if it is
  # not "active". Only the Net should emit 'tick'.
  tick: ->
    @debug = false
    @lastReal = @r
    @lastProb = @p
    @updateProb()
    @emit('updateImag')
    @r = 0.0

  # A String representation of the node state
  log: ->
    r = @r.toString().substr(0,4)
    p = @p.toString().substr(0,4)
    i = @i.toString().substr(0,4)
    "#{@name}\t#{@type}\tr:#{r}\tp:#{p}\ti:#{i}"

  # Calculate the current Real activation of this node. This is a separate
  # method from 'tick' because we might be able to skip it to save computations,
  # or it may be called multiple times within a discreet time step.
  update: () ->
    @updateReal()


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
    @p += (@r - @p) / @net.time


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
    vals.push(n.r * n.p) for n in @incoming
    @i = _.min([1.0, _.sum(vals)])
    callback()


class tnn.MinNode extends tnn.AggregatorNode
  type: 'Min'

  updateReal: (callback = ->) ->
    min = _.min(@incoming, (n) -> n.r)
    @r = min.r || 0
    callback()
    return @r


class tnn.MaxNode extends tnn.AggregatorNode
  type: 'Max'

  updateReal: (callback = ->) ->
    max = _.max @incoming, (n)-> n.r
    @r = max.r || 0
    callback()


class tnn.AverageNode extends tnn.AggregatorNode
  type: 'Avg'

  updateReal: (callback = ->) ->
    @r = (_.sum(_.pluck(@incoming, 'r')) / @incoming.length)
    callback()

class tnn.DelayNode extends tnn.BaseNode
  `/*
    Forwards its input after (int) @delay time steps
  */`

  constructor: (@net, @delay, outgoing = [], incoming = [], @name = '') ->
    @stored = []
    @shifted = false

    # Fill the storage with 0's to start
    while @stored.length < @delay
      @stored.push(0.0)
    @type = 'Delay:' + @delay
    super(net, outgoing, incoming, name)


  tick: ->
      super()
      @r = @stored.shift()
      @emit('incomingUpdate')


  updateReal: ->
    #Store highest Real Activation from incoming
    if @stored.length >= @delay
      # It's possible this can be called more than once in a discreet time step,
      # so we need to remove old values pushed into the store.
      @stored.pop()

    winner = _.max(_.pluck(@incoming, 'r'))
    @stored.push(winner || 0)

  log: ->
    l = super
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
