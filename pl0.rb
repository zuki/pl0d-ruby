$LOAD_PATH.unshift File.expand_path(File.dirname($PROGRAM_NAME)) # ruby 1.9 のため
require "compiler"

printTable = false;  # trueなら各ブロックの記号表を印字 
# objCode = false;   # trueなら目的コードを印字 
# trace = false;     # trueなら実行のトレース情報を印字 

unless "a".respond_to?:ord   # ruby 1.8 のため
  class String
     def ord
         self[0]
     end
  end
  class Integer
     def ord
         self
     end
  end
end

if ARGV.size == 2 && ARGV[0].size > 1 && ARGV[0][0] == "-"[0]
  ARGV[0][1, ARGV[0].size-1].each_byte do |ch|
    case ch
    when "s".ord then printTable = true
#    when "o".ord then objCode = true
#    when "t".ord then trace = true
    end
  end
  sourceFileName = ARGV[1]
elsif ARGV.size == 1
  sourceFileName = ARGV[0]
else
  print "USAGE: (-s)? sourceFileName\n"
  exit 1
end

compile(sourceFileName, printTable)


