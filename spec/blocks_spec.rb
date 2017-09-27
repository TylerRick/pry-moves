require_relative 'spec_helper'

describe 'PryMoves Commands' do


  it 'should go next over blocks' do
    breakpoints [
      [nil, 'stop in zaloop'],
      ['n', ''],
      # repeat commands
      ['', 'inside block'],
      ['', nil],

      ['s', 'stop in zaloop'],
      ['n', nil],
      ['', 'inside block'],
      ['pass', {out: '=> 0'}],

      ['f', 'after block'],
      ['pass', {out: '=> 0'}],

      ['f', 'post_yield'], # Тут хорошо бы, чтобы сразу шёл на "after block",
      # но пока и не понятно, как это угадать
      ['f', 'after block'],
      ['pass', {out: '=> :root'}],
    ]
    Playground.new.zaloop
  end

  it 'should finish simple block' do
    breakpoints [
      [nil, 'stop in with_simple_block'],
      ['n', ''],
      ['', 'inside block'],
      ['f', 'after block']
    ]
    Playground.new.with_simple_block
  end

  it 'should finish block with sub-calls' do
    breakpoints [
      [nil, 'stop in zaloop'],
      ['n', ''],
      ['', 'inside block'],
      ['f', 'after block'],
      ['pass', {out: '=> :root'}],
    ]
    Playground.new.zaloop
  end


end