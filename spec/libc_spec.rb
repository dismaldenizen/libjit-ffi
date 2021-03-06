($LOAD_PATH << File.dirname(File.expand_path(__FILE__))).uniq!
require 'spec_helper'

describe JIT::LibC do

let(:context) { JIT::Context.new }

describe "putchar" do
  let :func do
    context.build_function [:int32], :int32 do |f|
      res = f.c.putchar f.arg(0)
      f.return res
    end
  end
  subject { func }

  [65, 112, 104, 101, 120, 33].each do |x|
    context "when passed #{x}" do
      subject { func[x] }
      it "should print the character '#{x.chr}' successfully" do
        should eql(x)
      end
    end
  end
end

describe "time" do
  let :func do
    context.build_function [], :int64 do |f|
      res = f.c.time
      f.return res
    end
  end
  subject { func[] }

  it { should be_within(3).of(Time.now.to_i) }
end

describe "abs" do
  let :func do
    context.build_function [:int32], :int32 do |f|
      res = f.c.abs f.arg(0)
      f.return res
    end
  end
  subject { func }

  [65, -112, -104, 101, 120, -33, 0].each do |x|
    context "when passed #{x}" do
      subject { func[x] }
      it { should eql(x.abs) }
    end
  end
end

describe "malloc" do
  let :malloc do
    context.build_function [:int32], :pointer do |f|
      ptr = f.c.malloc f.arg(0)
      f.return ptr
    end
  end

  let :free do
    context.build_function [:pointer], :void do |f|
      f.c.free f.arg(0)
    end
  end

  [1, 10, 1024].each do |x|
    context "when passed #{x}" do
      it "should allocate #{x} bytes of usable memory" do
        ptr = malloc[x]
        array = []
        x.times { array << (rand * 256).to_i }
        ptr.put_array_of_uint8(0, array)
        ptr.get_array_of_uint8(0, x).should eql(array)
        free[ptr]
      end
    end
  end
end

describe "puts" do
  ruby_string = "Aphex Twin"
  
  let(:func) do
    context.build_function [], :int32 do |f|
      str = f.stringz(ruby_string)
      # Call puts and return result
      f.return(f.c.puts str)
    end
  end

  it "should print the string '#{ruby_string}' successfully" do
    func.call.should be >= 0
  end
end

describe "printf" do
  ruby_string = "[%d, %d]"
  
  let(:func) do
    context.build_function [], :int32 do |f|
      str = f.stringz(ruby_string)
      # Call puts and return result
      f.return(f.c.printf str, f.const(42, :int32), f.const(3, :int8))
    end
  end

  it "should print the string '[42, 3]' successfully" do
    func.call.should be >= 0
  end
end

after do
  context.destroy # Die monster, you don't belong in this world!
end
  
end

