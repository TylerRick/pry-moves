require 'pry' unless defined? Pry

module PryMoves
class Tracer

  def initialize(command, pry_start_options)
    @command = command
    @pry_start_options = pry_start_options
  end

  def trace
    @action = @command[:action]
    binding_ = @command[:binding]
    set_traced_method binding_

    case @action
    when :step
      @step_info_funcs = nil
      if (func = @command[:param])
        @step_info_funcs = [func]
        @step_info_funcs << 'initialize' if func == 'new'
      end
    when :finish
      @method_to_finish = @method
      @block_to_finish =
          (binding_.frame_type == :block) &&
              frame_digest(binding_)
    end

    start_tracing
  end

  private

  def start_tracing
    #puts "##trace_obj #{trace_obj}"
    Pry.config.disable_breakpoints = true
    trace_obj.set_trace_func method(:tracing_func).to_proc
  end

  def stop_tracing
    Pry.config.disable_breakpoints = false
    trace_obj.set_trace_func nil
  end

  # You can't call set_trace_func or Thread.current.set_trace_func recursively
  # even in different threads 😪
  # But! 💡
  # The hack is - you can call Thread.current.set_trace_func
  # from inside of set_trace_func! 🤗
  def trace_obj
    Thread.current[:pry_moves_debug] ?
        Thread.current : Kernel
  end

  def set_traced_method(binding)
    @recursion_level = 0

    method = binding.eval 'method(__method__) if __method__'
    if method
      source = method.source_location
      set_method({
       file: source[0],
       start: source[1],
       name: method.name,
       end: (source[1] + method.source.count("\n") - 1)
     })
    else
      set_method({file: binding.eval('__FILE__')})
    end
  end

  def set_method(method)
    #puts "set_traced_method #{method}"
    @method = method
  end

  def frame_digest(binding_)
    #puts "frame_digest for: #{binding_.eval '__callee__'}"
    Digest::MD5.hexdigest binding_.instance_variable_get('@iseq').disasm
  end

  def tracing_func(event, file, line, id, binding_, klass)
    #printf "#{trace_obj}: %8s %s:%-2d %10s %8s rec:#{@recursion_level}\n", event, file, line, id, klass

    # Ignore traces inside pry-moves code
    return if file && TRACE_IGNORE_FILES.include?(File.expand_path(file))

    catch (:skip) do
      if send "trace_#{@action}", event, file, line, binding_
        stop_tracing
        Pry.start(binding_, @pry_start_options)

      # for cases when currently traced method called more times recursively
      elsif %w(call return).include?(event) and within_current_method?(file, line) and
          @method[:name] == id # fix for bug in traced_method: return for dynamic methods has line number inside of caller
        delta = event == 'call' ? 1 : -1
        #puts "recursion #{event}: #{delta}; changed: #{@recursion_level} => #{@recursion_level + delta}"
        @recursion_level += delta
      end
    end
  end

  def trace_step(event, file, line, binding_)
    return unless event == 'line'
    if @step_info_funcs
      method = binding_.eval('__callee__').to_s
      @step_info_funcs.any? {|pattern| method.include? pattern}
    else
      true
    end
  end

  def trace_next(event, file, line, binding_)
    traced_method_exit = (@recursion_level < 0 and %w(line call).include? event)
    if traced_method_exit
      # Set new traced method, because we left previous one
      set_traced_method binding_
      throw :skip if event == 'call'
    end

    event == 'line' and
      @recursion_level == 0 and
      within_current_method?(file, line)
  end

  def trace_finish(event, file, line, binding_)
    return unless event == 'line'
    return true if @recursion_level < 0 or @method_to_finish != @method

    # for finishing blocks inside current method
    if @block_to_finish
      within_current_method?(file, line) and
          @block_to_finish != frame_digest(binding_.of_caller(3))
    end
  end

  def trace_debug(event, file, line, binding_)
    return unless event == 'line'
    if @first_line_skipped
      true
    else
      @first_line_skipped = true
      false
    end
  end

  def debug_info(file, line, id)
    puts "📽  Action:#{@action}; recur:#{@recursion_level}; #{@method[:file]}:#{file}"
    puts "#{id} #{@method[:start]} > #{line} > #{@method[:end]}"
  end

  def within_current_method?(file, line)
    @method[:file] == file and (
      @method[:start].nil? or
      line.between?(@method[:start], @method[:end])
    )
  end

end
end