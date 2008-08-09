# Compile a Ruby script to an embedable C header file containing an array
# of instruction sequences generated by YARV.
# Usage:
# 
#  ruby19 compile.rb boot boot.rb > boot.h
#
# Then include in your C code:
#
#  #include "boot.h"

raise "Ruby 1.9 required" unless RUBY_VERSION =~ /1\.9/

# Stolen from HotRuby: http://hotruby.accelart.jp/js/HotRuby.js
OUTPUT_COMPILE_OPTION = {
  :peephole_optimization    => true,
  :inline_const_cache       => false,
  :specialized_instruction  => false,
  :operands_unification     => false,
  :instructions_unification => false,
  :stack_caching            => false,
}

name, file = ARGV

iseq = VM::InstructionSequence.compile_file(file, OUTPUT_COMPILE_OPTION)

# iseq.to_a.each do |i|
#   puts i.inspect
# end
# exit

class InstructionConverter
  def initialize(name, iseq, &block)
    @name       = name
    @iseq       = iseq
    @out        = []
    @converters = {}
    @line       = 0
    @blocks     = []
    
    # special convertions
    convert :putobject do |cmds|
      type = case cmds[0]
      when Fixnum
        op :putfixnum, cmds[0]
      when Symbol
        op :putsymbol, cmds[0]
      else
        op :putspecial, cmds[0]
      end
    end
    convert :definemethod do |cmds|
      op :definemethod, cmds[0], cmds[1], cmds[2], cmds[1].last.size-1
    end
    convert :defineclass do |cmds|
      op :defineclass, cmds[0], cmds[1], cmds[2], cmds[1].last.size-1
    end
  end
  
  def convert(code, &block)
    @converters[code] = block
  end
  
  def op(code, *cmds)
    cmd = cmds.collect { |c| "(void *) #{convert_type(c)}" }.join(", ")
    @out << %Q(  { #{@line}, #{code.to_s.upcase}, { #{cmd} } },)
  end
  
  def convert_type(v)
    case v
    when Symbol
      %{"#{v}"}
    when NilClass
      "TR_NIL"
    when TrueClass
      "TR_TRUE"
    when FalseClass
      "TR_FALSE"
    when String
      v[0..2] == "TR_" ? v : v.inspect
    when Array
      key = "#{@name}__block_#{@blocks.size+1}"
      @blocks << InstructionConverter.new(key, v).to_s
      key
    else
      v.inspect
    end
  end
  
  def run
    @iseq.to_a.last.each do |inst|
      case inst
      when Fixnum # line number
        @line = inst
      when Symbol # label
        op :label, inst
      else
        if c = @converters[inst[0]]
          c.call(inst[1..-1])
        else
          op inst[0], *inst[1..-1]
        end
      end
    end
  end
  
  def to_s
    run
    @blocks.join("\n") <<
    "\n" <<
    "tr_op #{@name}[] = {\n" <<
    @out.join("\n") <<
    "\n};"
  end
end

puts '#ifndef _BOOT_H_'
puts '#define _BOOT_H_'
puts
puts '#include "tinyrb.h"'
puts

puts InstructionConverter.new("tr_boot_insts", iseq).to_s

puts '#endif /* _BOOT_H_ */'
