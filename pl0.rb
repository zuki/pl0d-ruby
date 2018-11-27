$LOAD_PATH.unshift File.expand_path(File.dirname($PROGRAM_NAME))
require 'optparse'
require "compiler"

printTable = false;  # trueなら各ブロックの記号表を印字
#objCode = false;   # trueなら目的コードを印字
#trace = false;     # trueなら実行のトレース情報を印字

opt = OptionParser.new
opt.on('-s') {|v| printTable = v }
#opt.on('-o') {|v| objCode = v }
#opt.on('-t') {|v| trace = v }
opt.parse!(ARGV)

unless ARGV
  print "USAGE: [-(s|o|t)] sourceFileName\n"
  exit 1
end
sourceFileName = ARGV[0]
compile(sourceFileName, printTable)
