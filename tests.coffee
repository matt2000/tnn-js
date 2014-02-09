tnn = require './tnn'
u = require 'underscore'

net = new tnn.Net(true)

testDelayMath = () ->
  #Strannegard 2012 - Figure 7.
  #Per disccussion with Prof. Strannegard, the top node should be Average, not Min as published.

  top = new tnn.AverageNode(net, [], [], 'top')
  a = new tnn.DelayNode(net, 4, [top], [], 'd4')
  b = new tnn.DelayNode(net, 3, [top], [], 'd3')
  c = new tnn.DelayNode(net, 2, [top], [], 'd2')
  d = new tnn.DelayNode(net, 1, [top], [], 'd1')
  e = new tnn.BaseNode(net, [top], [], 'd0')
  six = new tnn.BaseNode(net, [a], [], '6')
  times = new tnn.BaseNode(net, [b], [], '*')
  eight = new tnn.BaseNode(net, [c], [], '8')
  equals = new tnn.BaseNode(net, [d], [], '=')
  fortyeight = new tnn.BaseNode(net, [e], [], '48')

  six.activate()
  times.activate()
  eight.activate()
  equals.activate()
  fortyeight.activate()

  net.output()

  six.activate(1)
  #net.output()
  times.activate(1)
  #net.output()
  eight.activate(1)
  #net.output()
  equals.activate(1)
  net.tick(null)

  net.output()


  console.log "Real Activity in the top node", top.r, " should be 0.8:", top.r == 0.8

  console.log "Imaginary Activation of fortyeight should be > 0:", fortyeight.i > 0
  #console.log net
  return 1

testSequences = ->
  #Strannegard 2012 - Figure 8.

  net = new tnn.Net()
  minL = new tnn.MinNode(net, null, null, "123")
  minR = new tnn.MinNode(net, null, null, "124")
  a = new tnn.DelayNode(net, 2, [minL, minR])
  b = new tnn.DelayNode(net, 1, [minL, minR])
  c = new tnn.BaseNode(net, [minL])
  d = new tnn.BaseNode(net, [minR])
  one = new tnn.BaseNode(net, [a], [], 'one')
  two = new tnn.BaseNode(net, [b], [], 'two')
  three = new tnn.BaseNode(net, [c], [], 'three')
  four = new tnn.BaseNode(net, [d], [], 'four')


  one.activate()
  two.activate()
  three.activate()

  one.activate()
  two.activate()
  three.activate()
  net.output()

  one.activate()
  two.activate()
  four.activate()
  net.output()

  one.activate()
  two.activate()
  net.tick(null)
  net.output()


  console.log "Imaginary Activity of three", three.i, "should be greater than four", four.i, ":", three.i > four.i


testDelayMath(true)
testSequences()