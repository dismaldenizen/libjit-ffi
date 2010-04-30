module JIT

class Value
  attr_reader :jit_t
  
  def self.create(function, *args)
    raise ArgumentError.new "Function is required" unless function.is_a? Function
    raise ArgumentError.new "Type is required" if args.empty?
    type = Type.create *args
    wrap function, LibJIT.jit_value_create(function.jit_t, type.jit_t)
  end
  
  def self.wrap(function, jit_t)
    #TODO: infer function from jit_t, and remove function argument
    raise ArgumentError.new "Function can't be nil" if function.nil?
    
    v = Value.allocate
    v.instance_variable_set(:@function, function)
    v.instance_variable_set(:@jit_t, jit_t)
    
    type = v.type
    value = if type.struct?
      Struct.allocate
    elsif type.pointer?
      Pointer.allocate
    elsif type.void?
      Void.allocate
    else
      Primitive.allocate
    end
    
    value.instance_variable_set(:@function, function)
    value.instance_variable_set(:@jit_t, jit_t)
    # It's not strictly necessary to set @type, but we might as well
    # (caching FTW!)
    value.instance_variable_set(:@type, type)
    
    return value
  end
  
  def type
    @type ||= Type.wrap LibJIT.jit_value_get_type(jit_t)
  end
  
  def store(other)
    LibJIT.jit_insn_store(@function.jit_t, @jit_t, other.jit_t)
    self
  end
  
  # Gets address of variable (will be made addressable if not already).
  def address
    wrap_value LibJIT.jit_insn_address_of(@function.jit_t, @jit_t)
  end
  
  def addressable?
    LibJIT.jit_value_is_addressable(@jit_t) != 0
  end
  
  def set_addressable
    LibJIT.jit_value_set_addressable(@jit_t)
  end
  
  def to_bool
    wrap_value LibJIT.jit_insn_to_bool(@function.jit_t, @jit_t)
  end

  def cast *type
    type = Type.create *type
    wrap_value LibJIT.jit_insn_convert(@function.jit_t, jit_t, type.jit_t, 0)
  end
  
  private
  def wrap_value val
    Value.wrap @function, val
  end
end

class Void < Value
end

class Primitive < Value
  def <(other)
    wrap_value LibJIT.jit_insn_lt(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def <=(other)
    wrap_value LibJIT.jit_insn_le(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def >(other)
    wrap_value LibJIT.jit_insn_gt(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def >=(other)
    wrap_value LibJIT.jit_insn_ge(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def eq(other)
    wrap_value LibJIT.jit_insn_eq(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def ne(other)
    wrap_value LibJIT.jit_insn_ne(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def ~
    wrap_value LibJIT.jit_insn_not(@function.jit_t, @jit_t)
  end
  
  def <<(other)
    wrap_value LibJIT.jit_insn_shl(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def >>(other)
    wrap_value LibJIT.jit_insn_shr(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def &(other)
    wrap_value LibJIT.jit_insn_and(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def ^(other)
    wrap_value LibJIT.jit_insn_xor(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def |(other)
    wrap_value LibJIT.jit_insn_or(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def -@
    wrap_value LibJIT.jit_insn_neg(@function.jit_t, @jit_t)
  end
  
  def +(other)
    wrap_value LibJIT.jit_insn_add(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def -(other)
    wrap_value LibJIT.jit_insn_sub(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def *(other)
    wrap_value LibJIT.jit_insn_mul(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def /(other)
    wrap_value LibJIT.jit_insn_div(@function.jit_t, @jit_t, other.jit_t)
  end
  
  def %(other)
    wrap_value LibJIT.jit_insn_rem(@function.jit_t, @jit_t, other.jit_t)
  end
end

class Pointer < Primitive
  # Retrieves the value being pointed to. If an explicit type is not specified
  # it will be inferred.
  def dereference(type=nil)
    ref_type_jit_t = nil
    if type.nil?
      ref_type_jit_t = LibJIT.jit_type_get_ref(self.type.jit_t)
    else
      ref_type_jit_t = Type.create(type).jit_t
    end
    
    wrap_value LibJIT.jit_insn_load_relative(@function.jit_t, jit_t, 0, ref_type_jit_t)
  end

  # Stores a value at the address referenced by this pointer. An address offset
  # may optionally be set with a Ruby integer.
  def mstore(value, offset=0)
    LibJIT.jit_insn_store_relative(@function.jit_t, self.jit_t, offset, value.jit_t)
  end
end

class Struct < Value
  def [](index)
    wrap_value LibJIT.jit_insn_load_relative(@function.jit_t, self.address.jit_t, @type.offset(index), @type.field_type(index).jit_t)
  end
  
  def []=(index, value)
    LibJIT.jit_insn_store_relative(@function.jit_t, self.address.jit_t, @type.offset(index), value.jit_t)
  end
end

class Constant < Primitive
  def initialize(function, val, *type)
    raise ArgumentError.new "Function can't be nil" if function.nil?
    @function = function
    @type = Type.create *type
    
    @jit_t = case @type.to_sym
    when :uint8, :int8, :uint16, :int16, :uint32, :int32
      # Pass big unsigned integers as signed ones so FFI doesn't spit the dummy
      val = [val].pack('I').unpack('i').first if @type.unsigned?

      LibJIT.jit_value_create_nint_constant(@function.jit_t, @type.jit_t, val)
    when :uint64, :int64
      # Pass big unsigned integers as signed ones so FFI doesn't spit the dummy
      val = [val].pack('Q').unpack('q').first if @type.unsigned?
      
      LibJIT.jit_value_create_long_constant(@function.jit_t, @type.jit_t, val)
    when :float32
      raise NotImplementedError.new("TODO: float32 constant creation")
    when :float64
      raise NotImplementedError.new("TODO: float64 constant creation")
    else
      raise JIT::TypeError.new("'#{@sym}' is not a supported type for constant creation")
    end
  end
  
  def to_i
    @to_i ||= case type.to_sym
    when :uint8, :int8, :uint16, :int16, :uint32, :int32
      val = LibJIT.jit_value_get_nint_constant jit_t
      # Turn unsigned integer into a signed one if appropriate
      [val].pack('i').unpack('I').first if type.unsigned?
    when :uint64, :int64
      val = LibJIT.jit_value_get_long_constant jit_t
      # Turn unsigned integer into a signed one if appropriate
      [val].pack('q').unpack('Q').first if type.unsigned?
    else
      raise JIT::TypeError.new("Constant is not an integer")
    end
  end
end

end

