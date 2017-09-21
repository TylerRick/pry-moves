module PryStackExplorer
  class WhenStartedHook
    include Pry::Helpers::BaseHelpers

    def caller_bindings(target)
      bindings = binding.callers

      bindings = remove_internal_frames(bindings)
      bindings = remove_debugger_frames(bindings)
      bindings = bindings.drop(1) if pry_method_frame?(bindings.first)

      mark_vapid_frames(bindings)

      bindings
    end

    def call(target, options, _pry_)
      target ||= _pry_.binding_stack.first if _pry_
      options = {
        :call_stack    => true,
        :initial_frame => 0
      }.merge!(options)

      return if !options[:call_stack]

      if options[:call_stack].is_a?(Array)
        bindings = options[:call_stack]

        if !valid_call_stack?(bindings)
          raise ArgumentError, ":call_stack must be an array of bindings"
        end
      else
        bindings = caller_bindings(target)
      end

      PryStackExplorer.create_and_push_frame_manager bindings, _pry_, :initial_frame => options[:initial_frame]
    end

    private

    def mark_vapid_frames(bindings)
      stepped_out = false
      actual_file, actual_method = nil, nil

      bindings.each do |binding|
        if stepped_out
          if actual_file == binding.eval("__FILE__") and actual_method == binding.eval("__method__")
            stepped_out = false
          else
            binding.local_variable_set :vapid_frame, true
          end
        elsif binding.frame_type == :block
          stepped_out = true
          actual_file = binding.eval("__FILE__")
          actual_method = binding.eval("__method__")
        end

        if binding.local_variable_defined? :hide_from_stack
          binding.local_variable_set :vapid_frame, true
        end
      end
    end

    # remove internal frames related to setting up the session
    def remove_internal_frames(bindings)
      start_frames = internal_frames_with_indices(bindings)
      start_frame_index = start_frames.first.last

      if start_frames.size >= 2
        # god knows what's going on in here
        idx1, idx2 = start_frames.take(2).map(&:last)
        start_frame_index = idx2 if !nested_session?(bindings[idx1..idx2])
      end

      bindings.drop(start_frame_index + 1)
    end

    # remove pry-nav / pry-debugger / pry-byebug frames
    def remove_debugger_frames(bindings)
      bindings.drop_while { |b| b.eval("__FILE__") =~ /\/pry-/ }
    end

    # binding.pry frame
    # @return [Boolean]
    def pry_method_frame?(binding)
      safe_send(binding.eval("__method__"), :==, :pry)
    end

    # When a pry session is started within a pry session
    # @return [Boolean]
    def nested_session?(bindings)
      bindings.detect do |b|
        safe_send(b.eval("__method__"), :==, :re) &&
          safe_send(b.eval("self.class"), :equal?, Pry)
      end
    end

    # @return [Array<Array<Binding, Fixnum>>]
    def internal_frames_with_indices(bindings)
      bindings.each_with_index.select do |b, i|
        b.frame_type == :method and (
          safe_send(b.eval("self"), :equal?, Pry) and
            safe_send(b.eval("__method__"), :==, :start) or
          safe_send(b.eval("self"), :equal?, Binding) and
            safe_send(b.eval("__method__"), :==, :pry)
        )
      end
    end

    def valid_call_stack?(bindings)
      bindings.any? && bindings.all? { |v| v.is_a?(Binding) }
    end
  end
end
