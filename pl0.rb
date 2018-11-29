$LOAD_PATH.unshift File.expand_path(File.dirname($PROGRAM_NAME))
require "optparse"
require "pl0/codeGen"
require "pl0/compiler"
require "pl0/getSource"
require "pl0/table"

module PL0
  class PL0
    def initialize(sourceFileName, params)
      @compiler = Compiler.new(sourceFileName, params)
    end

    def run
      if (@compiler.run)
        @compiler.execute
      end
    end
  end
end

params = {s: false, l: false}   # s: 各ブロックの記号表を印字,
                                # l: コード表を印字

opt = OptionParser.new
opt.on('-s') {|v| params[:s] = v }
opt.on('-l') {|v| params[:l] = v }
opt.parse!(ARGV)

if ARGV.size == 0
  print "USAGE: [-s] [-l] sourceFileName\n"
  exit 1
end
sourceFileName = ARGV[0]

PL0::PL0.new(sourceFileName, params).run
