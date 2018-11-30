module PL0
  class Token
    # @kind  :_KeyWd, :_KeySym, :_UserId (:_FuncId, :_ParId, :_VarId), :_Num,
    # @value                 # トークン値
    # @symbol                # トークン名
    # @line                  # トークンが出現した行
    # @pos                   # トークンが出現した行内の位置
    # @prev                  # 一つ前のトークン
    attr_accessor :kind, :prev
    attr_reader :value, :symbol, :line, :pos

    def initialize(line, pos, k, sy, v)
      @line, @pos = line, pos, prev
      @kind, @symbol, @value = k, sy, v
    end

    def debug_line
      sprintf("sym: %s, val: %d, pos: %d", @symbol, @value, @pos)
    end

    def to_s
      @symbol.to_s
    end
  end

  class Log
    MAXERROR = 30          # これ以上のエラーがあったら終り
    @@error_no = 0

    def self.error(message, token, force_abort=false)
      header = token ? sprintf("[% 3d:% 3d]", token.line, token.pos) : "[---:---]"
      printf("%s %s\n", header, message);
      @@error_no += 1
      if (@@error_no > MAXERROR || force_abort)
        raise "too many errors"
      end
    end

    def self.errorN
      @@error_no
    end
  end

  class Lexer
    MAXNUM = 14            # 定数の最大桁数

    FIRSTADDR = 2  # 各ブロックの最初の変数のアドレス
    MINERROR = 3   # エラーがこれ以下なら実行

    def initialize(sourceFileName)
      @source = sourceFileName
    end

    def openSource
      @Fsource = File.open(@source, "r")
    end

    def closeSource
      @Fsource.close
    end

    def nextChar        #    次の１文字を返す関数
      if @lineIndex == -1
        if @line = @Fsource.gets
          @lineNo += 1
          @lineIndex = 0
        else
          errorF("end of file\n")    # end of fileならコンパイル終了
        end
      end
      ch = @line[@lineIndex]
      @lineIndex += 1
      if @lineIndex >= @line.size    # 1行を使い終わった
        @lineIndex = -1;             # 次の行の入力準備
        return "\n";                 # 文字としては改行文字を返す
      end
      return ch;
    end

    def position(len=0)
      @lineIndex > -1 ? @lineIndex - len : @line.size
    end

    def nextToken(prev)
      spaces = 0; cr = 0;
      while true                     # 空白や改行をカウント
        if @ch == " "
          spaces += 1
        elsif  @ch == "\t"
          spaces += TAB
        elsif @ch == "\n"
          spaces = 0;  cr += 1
        elsif @ch == "\r"
          # print("carriage return\n")
        else
          break
        end
        @ch = nextChar
      end
      case @charClassT[@ch.ord]
      when :letter           # identifier
        ident = ""
        begin
          ident << @ch
          @ch = nextChar
        end while ( @charClassT[@ch.ord] == :letter or @charClassT[@ch.ord] == :digit )
        ident = ident.downcase.to_sym
        case ident
        when :begin, :end, :if, :then, :while, :do, :return,
             :function, :var, :const, :odd, :write, :writeln
          temp = Token.new(@lineNo, position(ident.size), :_KeyWd, ident, 0)
        else       # ident == _UserId: ユーザの宣言した名前の場合
          temp = Token.new(@lineNo, position(ident.size), :_UserId, ident, 0)
        end
      when :digit            # number
        num = 0; i = 0
        begin
          num = 10 * num + @ch.to_i
          i += 1
          @ch = nextChar
        end while @charClassT[@ch.ord] == :digit
        temp = Token.new(@lineNo, position(num.to_s.size), :_Num, nil, num)
        error("too large", temp) if i > MAXNUM
      when :":"
        @ch = nextChar
        if @ch == '='                # ":="
          @ch = nextChar
          temp = Token.new(@lineNo, position(2), :_KeySym, :":=", 0)
        else
          temp = Token.new(@lineNo, position, nil, :"nil", 0)
        end
      when :"<"
        @ch = nextChar
        if @ch == '='                #    "<="
          @ch = nextChar
          temp = Token.new(@lineNo, position(2), :_KeySym, :"<=", 0)
        elsif @ch == '>'             #    "<>"
          @ch = nextChar
          temp = Token.new(@lineNo, position(2), :_KeySym, :"<>", 0)
        else
          temp = Token.new(@lineNo, position, :_KeySym, :"<", 0)
        end
      when :">"
        @ch = nextChar
        if @ch == '='                # ">="
          @ch = nextChar
          temp = Token.new(@lineNo, position(2), :_KeySym, :">=", 0)
        else
          temp = Token.new(@lineNo, position, :_KeySym, :">", 0)
        end
      else
        temp = Token.new(@lineNo, position, :_KeySym, @ch.to_sym, 0)
        @ch = nextChar
      end
      temp.prev = prev
      return temp
    end

    def isKeyWd(k)           # 識別子は予約語か
      case k
      when :begin, :end, :if, :then, :while, :do, :return,
           :function, :var, :const, :odd, :write, :writeln
         true
      else
         false
      end
    end

    def isKeySym(k)          # 識別子はユーザ指定の識別子か
      !isKeyWd(k)
    end

    def checkGet(t, s)      #    t: Tolen, s: t.symbol のチェック
      #    t.symbol == s なら、次のトークンを読んで返す
      #    t.symbol != s ならエラーメッセージを出し、t と s が共に記号、または予約語なら
      #    t を捨て、次のトークンを読んで返す（ t を s で置き換えたことになる）
      #    それ以外の場合、s を挿入したことにして、t を返す
      return nextToken(t) if t.symbol == s
      if ((isKeyWd(s) && t.kind == :_KeyWd) ||
        (isKeySym(s) && t.kind == :_KeySym))
        Log.error(sprintf("delete token: %s", t.symbol||t.value), t)
        Log.error(sprintf("insert '#{s}'", s), t)
        return nextToken(t)
      end
      Log.error("insert '#{s}'", t.prev)
      return t
    end

    def initCharClassT
      @charClassT = Array.new(256, :other)
      ("0".ord.."9".ord).each {|i| @charClassT[i] = :digit}
      ("A".ord.."Z".ord).each {|i| @charClassT[i] = :letter}
      ("a".ord.."z".ord).each {|i| @charClassT[i] = :letter}
      @charClassT["+".ord] = :"+"; @charClassT["-".ord] = :"-"
      @charClassT["*".ord] = :"*"; @charClassT["/".ord] = :"/"
      @charClassT["(".ord] = :"("; @charClassT[")".ord] = :")"
      @charClassT["=".ord] = :"="; @charClassT["<".ord] = :"<"
      @charClassT[">".ord] = :">"; @charClassT[",".ord] = :","
      @charClassT[".".ord] = :"."; @charClassT[";".ord] = :";"
      @charClassT[":".ord] = :":"
    end

    def initSource
      @errorNo = 0           # エラーの個数
      @lineNo = 0            # ソース行
      @lineIndex = -1        # ソース行内の文字位置
      @ch = "\n"             # ソースの現在位置の文字
      initCharClassT
    end

    def finalSource(t)
      Log.error("insert '.'", t) unless t.symbol == :"."
    end
  end
end
